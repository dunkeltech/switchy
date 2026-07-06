//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit

/// Tracks the "Most Recently Used" order of applications so the window list in the
/// overlay can be sorted sensibly.
///
/// MRU sorting happens at the app level (most recently activated app first). That is
/// enough for the core behavior: the most recently used *other* app/window sits at
/// position 2 and is therefore the default preselection.
final class MRUTracker {
    /// pids in MRU order – index 0 = most recently active.
    private var order: [pid_t] = []
    private var observer: NSObjectProtocol?

    func start() {
        // Adopt the current frontmost state initially.
        if let front = NSWorkspace.shared.frontmostApplication {
            promote(front.processIdentifier)
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.promote(app.processIdentifier)
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func promote(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }

    /// Sorts windows by their app's MRU rank. Windows of the same app keep their
    /// relative order (stable sort).
    func sorted(_ windows: [WindowInfo]) -> [WindowInfo] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return windows.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.pid] ?? Int.max
            let r = rank[rhs.element.pid] ?? Int.max
            if l != r { return l < r }
            return lhs.offset < rhs.offset          // stable
        }.map(\.element)
    }
}
