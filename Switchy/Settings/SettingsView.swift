//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import SwiftUI

/// The settings window: hotkeys, window behavior and startup behavior.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("Global switch") {
                    HotkeyRecorderView(combo: $settings.globalHotkey)
                        .frame(width: 160)
                }
                LabeledContent("In-app switch") {
                    HotkeyRecorderView(combo: $settings.appFilterHotkey)
                        .frame(width: 160)
                }
                LabeledContent("Reverse (during switching)") {
                    SingleKeyRecorderView(keyCode: $settings.reverseKeyCode)
                        .frame(width: 160)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Hold the modifier and tap the key; releasing confirms. To change, click the field and press the new combination. The reverse key steps the selection back one while the modifier is held (default: left ⇧).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window Behavior") {
                Toggle("Include minimized windows", isOn: $settings.includeMinimized)
                Toggle("Show windows from all displays/Spaces", isOn: $settings.showAllSpaces)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
    }
}
