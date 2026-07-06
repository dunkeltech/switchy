//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import SwiftUI

/// Borderless, floating overlay window that hosts the SwiftUI `OverlayView`.
///
/// Configured as a `.nonactivatingPanel` so that showing the overlay does not steal
/// focus from the current app (important for correctly focusing on confirm).
final class OverlayPanel: NSPanel {
    init(model: OverlayModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        // Visible on all Spaces so the overlay floats above everything.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        contentView = hosting
    }

    // Borderless panels cannot become key by default; we don't need that anyway
    // (nonactivating).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Centers the panel on the screen containing the mouse pointer and caps the
    /// width at 80 % of the screen width.
    func showCentered() {
        guard let screen = screenUnderMouse() else { return }

        // Fit the content size to the SwiftUI content, then cap it.
        contentView?.layoutSubtreeIfNeeded()
        let fitting = contentView?.fittingSize ?? NSSize(width: 400, height: 240)
        let maxWidth = screen.visibleFrame.width * 0.8
        let width = min(max(fitting.width, 200), maxWidth)
        let height = fitting.height

        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2
        )
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        orderFrontRegardless()
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
