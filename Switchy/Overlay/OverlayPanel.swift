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
    /// Minimum height matching `OverlayView`'s single-row frame (234 pt),
    /// preventing the panel from collapsing to 0 px when the model is still empty or
    /// `NSHostingView` has not laid out yet after a display/sleep transition.
    private static let minPanelHeight: CGFloat = 234

    private let model: OverlayModel

    init(model: OverlayModel) {
        self.model = model
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

    /// Centers the panel on the screen containing the mouse pointer, calculating the
    /// required columns and rows to fit comfortably, and capping the width and height
    /// at 80 % of the screen dimensions.
    func showCentered() {
        guard let screen = screenUnderMouse() else { return }

        let visible = screen.visibleFrame
        let maxWidth = visible.width * 0.8
        let maxHeight = visible.height * 0.8

        let count = model.windows.count
        if count == 0 {
            let width: CGFloat = 400
            let height = Self.minPanelHeight
            let origin = NSPoint(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2
            )
            alphaValue = 1.0
            setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
            orderFrontRegardless()
            return
        }

        // Maximum columns that fit horizontally without exceeding 80 % screen width:
        // Width for c columns: 40 + c * 236 + (c - 1) * 12 = 28 + 248 * c
        let maxCols = max(1, Int((maxWidth - 28) / 248))
        let columns: Int
        let rows: Int

        if count <= maxCols {
            columns = count
            rows = 1
        } else {
            rows = max(1, Int(ceil(Double(count) / Double(maxCols))))
            columns = min(maxCols, max(1, Int(ceil(Double(count) / Double(rows)))))
        }

        if model.columns != columns {
            model.columns = columns
        }

        let contentWidth = 28 + 248 * CGFloat(columns)
        let contentHeight = 28 + 206 * CGFloat(rows)

        let width = min(max(contentWidth, 200), maxWidth)
        let height = min(max(contentHeight, Self.minPanelHeight), maxHeight)

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
