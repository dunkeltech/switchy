//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Resolved display info for an app identified by its bundle identifier.
struct AppInfo: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?

    var id: String { bundleID }

    /// Resolves name and icon for a bundle identifier, even if the app is not running.
    static func resolve(_ bundleID: String) -> AppInfo {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return AppInfo(bundleID: bundleID, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        }
        return AppInfo(bundleID: bundleID, name: bundleID, icon: nil)
    }
}

/// Settings section to manage apps whose windows are hidden from the switcher.
struct ExcludedAppsSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            if settings.excludedBundleIDs.isEmpty {
                Text("No apps excluded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                    row(for: AppInfo.resolve(bundleID))
                }
            }

            Menu {
                ForEach(addableApps) { app in
                    Button(app.name) { add(app.bundleID) }
                }
                if !addableApps.isEmpty { Divider() }
                Button("Choose from Finder…") { chooseFromFinder() }
            } label: {
                Label("Add…", systemImage: "plus")
            }
            .frame(width: 120)
        } header: {
            Text("Excluded apps")
        } footer: {
            Text("Windows of these apps never appear in the switcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(for app: AppInfo) -> some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(app.name)
            Spacer()
            Button {
                settings.excludedBundleIDs.removeAll { $0 == app.bundleID }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove"))
        }
    }

    /// Currently running regular apps that are not already excluded (and not Switchy).
    private var addableApps: [AppInfo] {
        let excluded = Set(settings.excludedBundleIDs)
        let ownBundleID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppInfo? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != ownBundleID,
                      !excluded.contains(bundleID),
                      seen.insert(bundleID).inserted
                else { return nil }
                return AppInfo(bundleID: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ bundleID: String) {
        guard !settings.excludedBundleIDs.contains(bundleID) else { return }
        settings.excludedBundleIDs.append(bundleID)
    }

    private func chooseFromFinder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }
}
