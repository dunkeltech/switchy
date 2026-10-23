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
    /// Bundle identifiers whose windows are excluded entirely (e.g. "com.apple.Stickies").
    var excludedBundleIDs: Set<String> = []
}

/// Builds the combined window list from ScreenCaptureKit (visible windows incl.
/// `windowID`) and the Accessibility API (real titles, minimized windows, AX
/// reference for focusing).
final class WindowEnumerator {
    /// Windows with synthetic IDs (minimized windows without a CGWindowID) start above
    /// this offset to avoid collisions with real CGWindowIDs.
    static let syntheticIDBase: CGWindowID = 0xF000_0000

    /// Guard AX queries with a timeout so a hung process ("beachball") does not block
    /// enumeration.
    private let axMessagingTimeout: Float = 0.25

    /// Deadline for the ScreenCaptureKit query. Keeps a wedged SCK connection from
    /// hanging the whole enumeration (see `enumerateWindows`).
    /// Normal SCK queries return in < 30 ms; 0.4 s is generous while still fast enough
    /// that the user sees the overlay immediately on fallback.
    private let screenCaptureTimeout: Double = 0.4

    /// Cooldown duration (seconds) after ScreenCaptureKit fails or times out, during
    /// which subsequent enumerations skip SCK immediately and go straight to the
    /// Accessibility fallback instead of waiting for `screenCaptureTimeout` every time.
    private let screenCaptureCooldown: TimeInterval = 30.0

    /// Timestamp until which ScreenCaptureKit should be skipped (circuit breaker).
    private var skipScreenCaptureUntil: Date = .distantPast

    /// Resets the ScreenCaptureKit circuit breaker (e.g. after system wake).
    func resetScreenCaptureAvailability() {
        skipScreenCaptureUntil = .distantPast
    }

    /// Returns all switchable windows according to `options`.
    func enumerateWindows(options: EnumerationOptions = EnumerationOptions()) async -> [WindowInfo] {
        let ownPID = getpid()

        // 1) Visible windows via ScreenCaptureKit, guarded by a deadline and a
        //    short circuit-breaker cooldown.
        //    The ScreenCaptureKit connection can wedge after long uptime (or across
        //    sleep/wake) and then never return. Without a timeout the whole enumeration
        //    would hang and the overlay would stay empty until Switchy is restarted.
        //    On timeout/error we fall back to Accessibility-only enumeration below.
        let snapshots: [SCWindowSnapshot]?
        if Date() < skipScreenCaptureUntil {
            snapshots = nil
        } else {
            let timeout = screenCaptureTimeout
            let fetched: [SCWindowSnapshot]? = try? await withTimeout(seconds: timeout) {
                let content = try await SCShareableContent.current
                return content.windows.compactMap(SCWindowSnapshot.init)
            }
            if fetched == nil {
                skipScreenCaptureUntil = Date().addingTimeInterval(screenCaptureCooldown)
                NSLog("Switchy: ScreenCaptureKit unavailable/timed out – falling back to Accessibility")
            } else {
                skipScreenCaptureUntil = .distantPast
            }
            snapshots = fetched
        }
        let screenCaptureAvailable = snapshots != nil

        let scWindows = (snapshots ?? []).filter { window in
            guard window.windowLayer == 0,                // normal app windows
                  window.pid != ownPID,
                  !window.title.isEmpty,
                  window.frame.width > 40, window.frame.height > 40
            else { return false }
            // Windows on other Spaces are "off screen" – only include when requested.
            if !options.includeOtherSpaces, !window.isOnScreen { return false }
            if let bundleID = window.bundleID,
               options.excludedBundleIDs.contains(bundleID) { return false }
            if let filterPID = options.filterToPID, window.pid != filterPID { return false }
            if let rect = options.restrictToCGFrame {
                let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
                if !rect.contains(center) { return false }
            }
            return true
        }

        // 2) Build the AX window index per running app (titles + minimized windows).
        let axIndex = buildAXIndex(excludingPID: ownPID, excludedBundleIDs: options.excludedBundleIDs)

        var results: [WindowInfo] = []
        var matchedAXWindows = Set<AXUIElementBox>()

        // 3) Merge visible SCK windows with AX elements.
        for window in scWindows {
            let pid = window.pid
            let axMatch = axIndex[pid]?.match(title: window.title, frame: window.frame)
            if let axMatch { matchedAXWindows.insert(AXUIElementBox(axMatch)) }

            results.append(
                WindowInfo(
                    id: window.windowID,
                    title: window.title,
                    appName: window.appName,
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

        // 5) Add visible windows that SCK does not return as on-screen windows, via the
        //    Accessibility API (only real standard windows not already matched to an SCK
        //    window). This covers other Spaces – and doubles as the fallback when
        //    ScreenCaptureKit is unavailable, so the switcher keeps listing windows
        //    (with placeholder previews) instead of showing an empty overlay.
        if options.includeOtherSpaces || !screenCaptureAvailable {
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

    private func buildAXIndex(
        excludingPID ownPID: pid_t,
        excludedBundleIDs: Set<String>
    ) -> [pid_t: AppWindows] {
        var index: [pid_t: AppWindows] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid != ownPID else { continue }
            if let bundleID = app.bundleIdentifier, excludedBundleIDs.contains(bundleID) { continue }

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

/// Minimal, `Sendable` snapshot of an `SCWindow`. Lets the ScreenCaptureKit query run
/// inside a timeout-guarded child task without passing non-Sendable SCK objects across.
private struct SCWindowSnapshot {
    let windowID: CGWindowID
    let title: String
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let frame: CGRect
    let isOnScreen: Bool
    let windowLayer: Int

    init?(_ window: SCWindow) {
        guard let app = window.owningApplication else { return nil }
        windowID = window.windowID
        title = window.title ?? ""
        pid = app.processID
        bundleID = app.bundleIdentifier
        appName = app.applicationName
        frame = window.frame
        isOnScreen = window.isOnScreen
        windowLayer = window.windowLayer
    }
}

/// Thrown when a guarded async operation exceeds its deadline.
private struct TimeoutError: Error {}

/// Runs `operation` with a deadline, throwing `TimeoutError` if it does not finish in
/// time. Note: a truly hung operation cannot be force-killed – we simply stop waiting
/// for it and let the caller fall back.
func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimeoutError() }
        return result
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
