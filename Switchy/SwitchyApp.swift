//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import SwiftUI

/// Application entry point.
///
/// The app is a pure menu bar agent (`LSUIElement = YES`), so it deliberately has
/// no `WindowGroup`/`Scene` with a visible window. All control flows through the
/// `AppDelegate`.
@main
struct SwitchyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `Settings` creates no visible scene at launch and keeps the SwiftUI app
        // structure valid. The "Settings…" menu item is handled by the AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
