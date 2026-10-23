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

    private var panel: OverlayPanel?
    private var panelNeedsRecreation = false
    private var systemObservers: [NSObjectProtocol] = []

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

    /// Mode of the most recent activation – used to re-open in the same mode when
    /// recovering from a wedged session (see `hotkeyStep`).
    private var lastMode: SwitchMode = .global

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
        registerSystemObservers()
    }

    func stop() {
        mru.stop()
        unregisterSystemObservers()
        destroyPanel()
    }

    /// Listens for system sleep/wake, display sleep/wake, and screen configuration
    /// changes so the overlay panel and ScreenCaptureKit state are refreshed cleanly.
    private func registerSystemObservers() {
        unregisterSystemObservers()

        let wsCenter = NSWorkspace.shared.notificationCenter
        let wakeNotifications: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in wakeNotifications {
            let token = wsCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if note.name != NSWorkspace.activeSpaceDidChangeNotification {
                        self.enumerator.resetScreenCaptureAvailability()
                        self.panelNeedsRecreation = true
                        if self.isOverlayActive {
                            self.resetSession()
                        }
                    } else if !self.isOverlayActive {
                        // Mark for fresh creation on next invocation after a Space switch.
                        self.panelNeedsRecreation = true
                    }
                }
            }
            systemObservers.append(token)
        }

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panelNeedsRecreation = true
            }
        }
        systemObservers.append(screenToken)
    }

    private func unregisterSystemObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for token in systemObservers {
            wsCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        systemObservers.removeAll()
    }

    /// Returns the active `OverlayPanel`, recreating it if none exists or if a sleep/wake,
    /// display reconfiguration, or Space transition invalidated the previous window surface.
    private func ensureFreshPanel() -> OverlayPanel {
        if panelNeedsRecreation || panel == nil {
            destroyPanel()
            panelNeedsRecreation = false
        }
        if let existing = panel {
            return existing
        }
        let created = OverlayPanel(model: model)
        panel = created
        return created
    }

    private func destroyPanel() {
        if let existing = panel {
            existing.orderOut(nil)
            existing.close()
            panel = nil
        }
    }

    // MARK: - HotkeyResponder

    func hotkeyActivate(mode: SwitchMode, reverse: Bool) {
        lastMode = mode
        // Recover from a wedged previous session: if we still believe the overlay is
        // active, tear it down first instead of ignoring the hotkey (which would make
        // the switcher silently stop appearing until Switchy is restarted).
        if isOverlayActive { resetSession() }

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
        let activePanel = ensureFreshPanel()
        activePanel.showCentered()

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

            self.panel?.showCentered() // re-fit (width depends on the count)

            // Load previews (can take a moment) and update the view.
            result = await self.previewCapture.loadPreviews(for: result)
            guard self.session == currentSession, self.isOverlayActive else { return }
            self.windows = result
            self.model.windows = result
        }
    }

    func hotkeyStep(reverse: Bool) {
        guard isOverlayActive else { return }

        // Recovery: we think a session is active, but the overlay isn't actually on
        // screen. The previous session got wedged (e.g. a confirm/cancel event was
        // missed). Re-open fresh so the switcher reappears instead of silently
        // stepping an invisible overlay – this is what otherwise "needs a restart".
        if panel == nil || panel?.isVisible != true {
            NSLog("Switchy: recovering wedged overlay session (was active but not visible)")
            panelNeedsRecreation = true
            hotkeyActivate(mode: lastMode, reverse: reverse)
            return
        }

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
            panel?.orderOut(nil)
            return
        }

        finishConfirm(session: session)
    }

    func hotkeyCancel() {
        guard isOverlayActive else { return }
        resetSession()
    }

    /// Tears down the current session and hides the overlay, invalidating any running
    /// async task via the session counter. Leaves the app ready for a fresh activation.
    private func resetSession() {
        isOverlayActive = false
        pendingConfirm = false
        windowsLoaded = false
        session += 1
        panel?.orderOut(nil)
    }

    /// Performs the actual window switch and ends the session.
    private func finishConfirm(session expected: Int) {
        guard isOverlayActive, session == expected else { return }
        isOverlayActive = false
        pendingConfirm = false
        session += 1
        panel?.orderOut(nil)

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
            ?? NSScreen.main
            ?? NSScreen.screens.first,
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
