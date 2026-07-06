//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import ScreenCaptureKit

/// Checks and requests the two permissions the app strictly requires:
/// **Accessibility** and **Screen Recording**.
///
/// Neither permission can be granted silently at runtime – the user must set them in
/// System Settings. Therefore, when a permission is missing, the app shows an
/// explanatory dialog with a deep link.
final class PermissionsManager {
    static let shared = PermissionsManager()

    private init() {}

    /// Checks both permissions. `granted` is called as soon as at least Accessibility
    /// is available (required for the event tap). If a permission is missing, an
    /// informational dialog is shown.
    func ensurePermissions(granted: @escaping () -> Void) {
        let accessibility = hasAccessibilityPermission(prompt: true)

        // Screen Recording triggers the system prompt on the first `SCShareableContent`
        // access anyway; check it up front here for the dialog.
        checkScreenRecordingPermission { [weak self] screenRecording in
            DispatchQueue.main.async {
                if !accessibility || !screenRecording {
                    self?.showPermissionAlert(
                        accessibility: accessibility,
                        screenRecording: screenRecording
                    )
                }
                if accessibility {
                    granted()
                }
            }
        }
    }

    // MARK: - Accessibility

    /// `prompt: true` shows the system's own permission dialog the first time.
    @discardableResult
    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Screen Recording

    /// Determines (asynchronously) whether Screen Recording is granted.
    /// `SCShareableContent` returns/throws nothing usable without the permission.
    func checkScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            completion(error == nil && content != nil)
        }
    }

    // MARK: - Dialog

    private func showPermissionAlert(accessibility: Bool, screenRecording: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Permissions required")

        var missing: [String] = []
        if !accessibility { missing.append(String(localized: "• Accessibility")) }
        if !screenRecording { missing.append(String(localized: "• Screen Recording")) }

        let template = String(localized: "Switchy needs the following permissions to switch windows and show previews:\n\n%@\n\nPlease enable them in System Settings and then restart the app.")
        alert.informativeText = String(format: template, missing.joined(separator: "\n"))

        if !accessibility {
            alert.addButton(withTitle: String(localized: "Open Accessibility"))
        }
        if !screenRecording {
            alert.addButton(withTitle: String(localized: "Open Screen Recording"))
        }
        alert.addButton(withTitle: String(localized: "Later"))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        // Buttons are added in the order above.
        var index = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if !accessibility {
            if response.rawValue == index { openSettings(.accessibility) }
            index += 1
        }
        if !screenRecording {
            if response.rawValue == index { openSettings(.screenRecording) }
        }
    }

    private enum SettingsPane {
        case accessibility
        case screenRecording

        var urlString: String {
            switch self {
            case .accessibility:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .screenRecording:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            }
        }
    }

    private func openSettings(_ pane: SettingsPane) {
        if let url = URL(string: pane.urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
