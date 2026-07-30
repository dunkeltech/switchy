//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit

/// Manages the app lifecycle, the menu bar icon, and starts the central controllers
/// (permissions, event tap, overlay).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let overlayController = OverlayController()
    private lazy var eventTap = EventTapController(handler: overlayController)
    private var tapWatchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, don't activate as a regular app.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()

        // Start MRU tracking as early as possible so the order is already populated
        // before the first overlay invocation.
        overlayController.start()

        // Check permissions and guide the user if needed.
        PermissionsManager.shared.ensurePermissions { [weak self] in
            // Only start the event tap once Accessibility is granted – otherwise
            // `CGEventTapCreate` fails.
            self?.eventTap.start()
        }

        startTapWatchdog()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapWatchdog?.invalidate()
        eventTap.stop()
        overlayController.stop()
    }

    /// Keeps the event tap healthy over long uptimes. Two things can silently kill it:
    /// macOS disabling the tap (slow callback, sleep/wake) and the Accessibility grant
    /// being dropped (ad-hoc-signed builds lose it when the app is rebuilt/updated).
    /// Both leave Switchy running but unresponsive to the hotkey until it is restarted.
    /// Polling here re-enables/recreates the tap automatically – no restart needed.
    private func startTapWatchdog() {
        tapWatchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.eventTap.isRunning else { return }
                if PermissionsManager.shared.hasAccessibilityPermission(prompt: false) {
                    self.eventTap.start()
                }
            }
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Custom monochrome logo (template image from the asset catalog);
            // falls back to an SF Symbol if the asset is missing.
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Switchy")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        PreferencesWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
