//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit

/// Connects the event tap, window enumeration, MRU sorting, preview capturing and the
/// overlay panel into the full switching flow.
@MainActor
final class OverlayController: HotkeyResponder {
    private let model = OverlayModel()
    private let enumerator = WindowEnumerator()
    private let previewCapture = PreviewCapture()
    private let mru = MRUTracker()

    private lazy var panel = OverlayPanel(model: model)

    /// Windows in current display order.
    private var windows: [WindowInfo] = []
    /// Running index within the current gesture session (may be negative/out of range
    /// before loading; brought into range via `normalizeSelection()`).
    private var selectedIndex = 0

    private(set) var isOverlayActive = false

    /// Whether the current session's window list has already been loaded.
    private var windowsLoaded = false
    /// Set when the user confirmed before the list was loaded – the switch is then
    /// performed once enumeration finishes.
    private var pendingConfirm = false

    /// Monotonically increasing – identifies the current overlay session so that late
    /// async results of a cancelled session are discarded.
    private var session = 0

    init() {
        model.onActivate = { [weak self] index in
            self?.selectedIndex = index
            self?.hotkeyConfirm()
        }
        model.onHover = { [weak self] index in
            guard let self, self.isOverlayActive else { return }
            self.selectedIndex = index
            self.model.selectedIndex = index
        }
    }

    // MARK: - Lifecycle

    func start() {
        mru.start()
    }

    func stop() {
        mru.stop()
    }

    // MARK: - HotkeyResponder

    func hotkeyActivate(mode: SwitchMode, reverse: Bool) {
        guard !isOverlayActive else { return }
        isOverlayActive = true
        windowsLoaded = false
        pendingConfirm = false
        session += 1
        let currentSession = session

        // Preselection: second window in the MRU list (or last one when reversing).
        selectedIndex = reverse ? -1 : 1
        windows = []
        model.windows = []

        let options = enumerationOptions(for: mode)

        previewCapture.invalidate()
        panel.showCentered()

        Task { [weak self] in
            guard let self else { return }
            var result = self.mru.sorted(
                await self.enumerator.enumerateWindows(options: options)
            )
            // Only check the session validity (not isOverlayActive) – an already
            // performed confirm should still run here.
            guard self.session == currentSession else { return }

            self.windows = result
            self.windowsLoaded = true
            self.normalizeSelection()
            self.model.windows = result
            self.model.selectedIndex = self.selectedIndex

            // Quick tap: the user already released before loading finished →
            // perform the switch now and end.
            if self.pendingConfirm {
                self.finishConfirm(session: currentSession)
                return
            }

            self.panel.showCentered() // re-fit (width depends on the count)

            // Load previews (can take a moment) and update the view.
            result = await self.previewCapture.loadPreviews(for: result)
            guard self.session == currentSession, self.isOverlayActive else { return }
            self.windows = result
            self.model.windows = result
        }
    }

    func hotkeyStep(reverse: Bool) {
        guard isOverlayActive else { return }
        selectedIndex += reverse ? -1 : 1
        if windowsLoaded {
            normalizeSelection()
            model.selectedIndex = selectedIndex
        }
    }

    func hotkeyConfirm() {
        guard isOverlayActive else { return }

        // List not loaded yet → defer the confirmation, hide the overlay. The running
        // enumeration task performs the switch afterwards.
        guard windowsLoaded else {
            pendingConfirm = true
            panel.orderOut(nil)
            return
        }

        finishConfirm(session: session)
    }

    func hotkeyCancel() {
        guard isOverlayActive else { return }
        isOverlayActive = false
        pendingConfirm = false
        session += 1 // invalidate running async tasks
        panel.orderOut(nil)
    }

    /// Performs the actual window switch and ends the session.
    private func finishConfirm(session expected: Int) {
        guard isOverlayActive, session == expected else { return }
        isOverlayActive = false
        pendingConfirm = false
        session += 1
        panel.orderOut(nil)

        if windows.indices.contains(selectedIndex) {
            WindowActivator.activate(windows[selectedIndex])
        }
    }

    // MARK: - Helpers

    /// Builds the enumeration options from the settings and the mode.
    private func enumerationOptions(for mode: SwitchMode) -> EnumerationOptions {
        let settings = AppSettings.shared
        var options = EnumerationOptions()
        options.includeMinimized = settings.includeMinimized
        options.excludedBundleIDs = Set(settings.excludedBundleIDs)

        if mode == .appFilter {
            // Before the (non-activating) overlay appears, the most recently active app
            // is still frontmost – we filter its windows.
            options.filterToPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        }

        if settings.showAllSpaces {
            // Include windows from other Spaces/displays.
            options.includeOtherSpaces = true
        } else {
            // Restrict to the screen under the mouse pointer (current Space).
            options.restrictToCGFrame = Self.cgFrameOfScreenUnderMouse()
        }

        return options
    }

    /// Frame of the screen under the mouse pointer in CoreGraphics coordinates
    /// (top-left origin), matching `SCWindow.frame`.
    private static func cgFrameOfScreenUnderMouse() -> CGRect? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main,
              let primary = NSScreen.screens.first
        else { return nil }

        // Convert Cocoa (bottom-left origin) → CG (top-left origin).
        let primaryHeight = primary.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }

    /// Brings `selectedIndex` into the valid range with wrap-around.
    private func normalizeSelection() {
        let count = windows.count
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = ((selectedIndex % count) + count) % count
    }
}
