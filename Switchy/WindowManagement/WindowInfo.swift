//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit

/// Describes a single switchable window shown in the overlay.
///
/// Holds both the CoreGraphics/ScreenCaptureKit view (`windowID`) and the
/// Accessibility view (`axElement`), because both are needed for different tasks:
/// `windowID` for capturing, `axElement` for focusing/unminimizing.
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appIcon: NSImage?
    let pid: pid_t
    let isMinimized: Bool

    /// Reference to the AX window element (for raise/unminimize). Optional, since not
    /// every CG window has a matching AX window (e.g. system UI).
    let axElement: AXUIElement?

    /// Preview image of the window content, or a placeholder. Filled asynchronously
    /// after enumeration, hence `var`.
    var previewImage: NSImage?

    var windowID: CGWindowID { id }

    /// Short title for display: uses the window title, falling back to the app name.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }
}
