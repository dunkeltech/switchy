//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import ScreenCaptureKit

/// Filter options for window enumeration.
struct EnumerationOptions {
    /// Include minimized windows.
    var includeMinimized: Bool = true
    /// Only windows of this app (PID) – for the in-app switcher.
    var filterToPID: pid_t? = nil
    /// Restrict visible windows to this area (CoreGraphics coordinates, top-left
    /// origin). For "current screen/Space only".
    var restrictToCGFrame: CGRect? = nil
    /// Include windows from other Spaces (virtual desktops). Such windows count as
    /// "off screen" and are otherwise filtered out.
    var includeOtherSpaces: Bool = false
}

/// Builds the combined window list from ScreenCaptureKit (visible windows incl.
/// `windowID`) and the Accessibility API (real titles, minimized windows, AX
/// reference for focusing).
final class WindowEnumerator {
    /// Windows with synthetic IDs (minimized windows without a CGWindowID) start above
    /// this offset to avoid collisions with real CGWindowIDs.
    private static let syntheticIDBase: CGWindowID = 0xF000_0000

    /// Guard AX queries with a timeout so a hung process ("beachball") does not block
    /// enumeration.
    private let axMessagingTimeout: Float = 0.25

    /// Returns all switchable windows according to `options`.
    func enumerateWindows(options: EnumerationOptions = EnumerationOptions()) async -> [WindowInfo] {
        let ownPID = getpid()

        // 1) Visible windows via ScreenCaptureKit.
        let scWindows: [SCWindow]
        do {
            let content = try await SCShareableContent.current
            scWindows = content.windows.filter { window in
                guard window.windowLayer == 0,                // normal app windows
                      let pid = window.owningApplication?.processID, pid != ownPID,
                      !(window.title ?? "").isEmpty,
                      window.frame.width > 40, window.frame.height > 40
                else { return false }
                // Windows on other Spaces are "off screen" – only include when requested.
                if !options.includeOtherSpaces, !window.isOnScreen { return false }
                if let filterPID = options.filterToPID, pid != filterPID { return false }
                if let rect = options.restrictToCGFrame {
                    let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
                    if !rect.contains(center) { return false }
                }
                return true
            }
        } catch {
            scWindows = []
        }

        // 2) Build the AX window index per running app (titles + minimized windows).
        let axIndex = buildAXIndex(excludingPID: ownPID)

        var results: [WindowInfo] = []
        var matchedAXWindows = Set<AXUIElementBox>()

        // 3) Merge visible SCK windows with AX elements.
        for window in scWindows {
            guard let app = window.owningApplication else { continue }
            let pid = app.processID
            let axMatch = axIndex[pid]?.match(title: window.title ?? "", frame: window.frame)
            if let axMatch { matchedAXWindows.insert(AXUIElementBox(axMatch)) }

            results.append(
                WindowInfo(
                    id: window.windowID,
                    title: window.title ?? "",
                    appName: app.applicationName,
                    appIcon: NSRunningApplication(processIdentifier: pid)?.icon,
                    pid: pid,
                    isMinimized: false,
                    axElement: axMatch,
                    previewImage: nil
                )
            )
        }

        // Synthetic IDs for windows without an on-screen SCK entry (minimized or on
        // another Space).
        var synthetic = Self.syntheticIDBase

        // 4) Add minimized AX windows (they have no on-screen SCK window). The screen
        //    restriction does not apply here (minimized windows have no meaningful
        //    frame/Space).
        if options.includeMinimized {
            for (pid, appWindows) in axIndex {
                if let filterPID = options.filterToPID, pid != filterPID { continue }
                for axWindow in appWindows.minimizedWindows {
                    guard !matchedAXWindows.contains(AXUIElementBox(axWindow)) else { continue }
                    let title = AX.string(axWindow, kAXTitleAttribute as String) ?? ""
                    results.append(
                        WindowInfo(
                            id: synthetic,
                            title: title,
                            appName: appWindows.appName,
                            appIcon: NSRunningApplication(processIdentifier: pid)?.icon,
                            pid: pid,
                            isMinimized: true,
                            axElement: axWindow,
                            previewImage: nil
                        )
                    )
                    synthetic += 1
                }
            }
        }

        // 5) Add visible windows from other Spaces that SCK does not return as
        //    on-screen windows, via the Accessibility API (only real standard windows
        //    not already matched to an SCK window).
        if options.includeOtherSpaces {
            for (pid, appWindows) in axIndex {
                if let filterPID = options.filterToPID, pid != filterPID { continue }
                for entry in appWindows.visibleWindows {
                    guard !matchedAXWindows.contains(AXUIElementBox(entry.element)) else { continue }
                    guard !entry.title.isEmpty else { continue }
                    let subrole = AX.string(entry.element, kAXSubroleAttribute as String)
                    guard subrole == (kAXStandardWindowSubrole as String) else { continue }
                    results.append(
                        WindowInfo(
                            id: synthetic,
                            title: entry.title,
                            appName: appWindows.appName,
                            appIcon: NSRunningApplication(processIdentifier: pid)?.icon,
                            pid: pid,
                            isMinimized: false,
                            axElement: entry.element,
                            previewImage: nil
                        )
                    )
                    synthetic += 1
                }
            }
        }

        return results
    }

    // MARK: - AX index

    private func buildAXIndex(excludingPID ownPID: pid_t) -> [pid_t: AppWindows] {
        var index: [pid_t: AppWindows] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != ownPID else { continue }

            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, axMessagingTimeout)

            let windows = AX.elements(appElement, kAXWindowsAttribute as String)
            guard !windows.isEmpty else { continue }

            var minimized: [AXUIElement] = []
            var all: [(element: AXUIElement, title: String, frame: CGRect?)] = []
            for window in windows {
                let title = AX.string(window, kAXTitleAttribute as String) ?? ""
                if AX.bool(window, kAXMinimizedAttribute as String) {
                    minimized.append(window)
                } else {
                    all.append((window, title, AX.frame(window)))
                }
            }
            index[pid] = AppWindows(
                appName: app.localizedName ?? "",
                visibleWindows: all,
                minimizedWindows: minimized
            )
        }
        return index
    }
}

/// An app's AX windows, grouped into visible/minimized.
private struct AppWindows {
    let appName: String
    let visibleWindows: [(element: AXUIElement, title: String, frame: CGRect?)]
    let minimizedWindows: [AXUIElement]

    /// Finds the AX window that best matches an SCK window: first by title, otherwise
    /// by frame overlap.
    func match(title: String, frame: CGRect) -> AXUIElement? {
        if !title.isEmpty, let byTitle = visibleWindows.first(where: { $0.title == title }) {
            return byTitle.element
        }
        // Fallback: frame with the largest overlap (titles may differ).
        var best: (element: AXUIElement, area: CGFloat)?
        for candidate in visibleWindows {
            guard let candidateFrame = candidate.frame else { continue }
            let overlap = candidateFrame.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (candidate.element, area)
            }
        }
        return best?.element
    }
}

/// Makes `AXUIElement` usable in a `Set` (identity-based).
private struct AXUIElementBox: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }

    static func == (lhs: AXUIElementBox, rhs: AXUIElementBox) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
