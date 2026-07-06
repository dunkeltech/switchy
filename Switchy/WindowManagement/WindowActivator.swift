//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit

/// Brings a selected window to the front and unminimizes it if needed.
enum WindowActivator {
    /// Focuses the window: unminimize → activate app → raise AX window.
    ///
    /// If the window is on another Space, activating it automatically triggers the
    /// system Space-switch animation.
    static func activate(_ window: WindowInfo) {
        // 1) Unminimize (if needed) via the Accessibility API.
        if window.isMinimized, let axElement = window.axElement {
            AX.setBool(axElement, kAXMinimizedAttribute as String, false)
        }

        // 2) Bring the app to the front.
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateAllWindows])
        }

        // 3) Raise the specific window and mark it as the main window.
        if let axElement = window.axElement {
            AX.perform(axElement, kAXRaiseAction as String)
            AX.setBool(axElement, kAXMainAttribute as String, true)
        }
    }
}
