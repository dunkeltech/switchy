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
    /// Minimum height matching `OverlayView`'s fixed frame (`itemHeight + 40 + 44 = 234`),
    /// preventing the panel from collapsing to 0 px when the model is still empty or
    /// `NSHostingView` has not laid out yet after a display/sleep transition.
    private static let minPanelHeight: CGFloat = 234

    init(model: OverlayModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: Self.minPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
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
        contentView?.needsLayout = true
        contentView?.layoutSubtreeIfNeeded()
        let fitting = contentView?.fittingSize ?? NSSize(width: 400, height: Self.minPanelHeight)
        let maxWidth = screen.visibleFrame.width * 0.8
        let width = min(max(fitting.width, 200), maxWidth)
        let height = max(fitting.height, Self.minPanelHeight)

        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2
        )
        alphaValue = 1.0
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        orderFrontRegardless()
        contentView?.needsDisplay = true
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
