//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import Combine

/// Central, persistent configuration (backed by UserDefaults). Changes are saved
/// immediately and bound to the SwiftUI interface via `@Published`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var globalHotkey: KeyCombo { didSet { store(globalHotkey, Keys.globalHotkey) } }
    @Published var appFilterHotkey: KeyCombo { didSet { store(appFilterHotkey, Keys.appFilterHotkey) } }
    /// Keycode of the key that steps the selection back one during an active switch
    /// (default: left ⇧ key, keycode 56).
    @Published var reverseKeyCode: UInt16 { didSet { defaults.set(Int(reverseKeyCode), forKey: Keys.reverseKeyCode) } }
    @Published var includeMinimized: Bool { didSet { defaults.set(includeMinimized, forKey: Keys.includeMinimized) } }
    @Published var showAllSpaces: Bool { didSet { defaults.set(showAllSpaces, forKey: Keys.showAllSpaces) } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            let ok = LaunchAtLogin.setEnabled(launchAtLogin)
            // If the system rejects the change, mirror the real status back.
            if !ok || LaunchAtLogin.isEnabled != launchAtLogin {
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
    }

    private enum Keys {
        static let globalHotkey = "globalHotkey"
        static let appFilterHotkey = "appFilterHotkey"
        static let reverseKeyCode = "reverseKeyCode"
        static let includeMinimized = "includeMinimized"
        static let showAllSpaces = "showAllSpaces"
    }

    private init() {
        // Defaults per the specification.
        globalHotkey = Self.load(Keys.globalHotkey, defaults)
            ?? KeyCombo(keyCode: 48, modifiers: .option)          // ⌥⇥
        appFilterHotkey = Self.load(Keys.appFilterHotkey, defaults)
            ?? KeyCombo(keyCode: 50, modifiers: .option)          // ⌥`
        reverseKeyCode = UInt16(defaults.object(forKey: Keys.reverseKeyCode) as? Int ?? 56) // left ⇧
        includeMinimized = defaults.object(forKey: Keys.includeMinimized) as? Bool ?? true
        showAllSpaces = defaults.object(forKey: Keys.showAllSpaces) as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: - Persistence for KeyCombo

    private func store(_ combo: KeyCombo, _ key: String) {
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(_ key: String, _ defaults: UserDefaults) -> KeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }
}
