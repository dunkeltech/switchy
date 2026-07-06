//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService` to (un)register the app as a login item.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or removes the login-item entry. Errors are logged and returned as
    /// `false` (success = yes/no).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
            return true
        } catch {
            NSLog("Switchy: LaunchAtLogin(\(enabled)) failed: \(error.localizedDescription)")
            return false
        }
    }
}
