//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import AppKit
import ScreenCaptureKit

/// Creates preview images for windows via ScreenCaptureKit and caches them.
///
/// Minimized windows have no image buffer – for those a placeholder is rendered from
/// the app icon with a "Minimized" badge.
final class PreviewCapture {
    /// Maximum thumbnail edge length (performance/memory).
    private let maxDimension: CGFloat = 640

    /// Deadline for ScreenCaptureKit calls so a wedged SCK daemon cannot stall preview
    /// loading indefinitely.
    private let captureTimeout: Double = 0.5

    private var cache: [CGWindowID: NSImage] = [:]

    /// Discards the cache – call when the overlay is reopened so previews are current.
    func invalidate() {
        cache.removeAll()
    }

    /// Fills `previewImage` for all given windows (in parallel where possible).
    func loadPreviews(for windows: [WindowInfo]) async -> [WindowInfo] {
        // Only query ScreenCaptureKit if there is at least one non-minimized window
        // with a real CGWindowID (below syntheticIDBase) not yet in cache. When
        // enumeration already fell back to Accessibility (all IDs >= syntheticIDBase),
        // skipping SCK here avoids hanging on a wedged ScreenCaptureKit connection and
        // immediately populates placeholder cards.
        let needsLiveCapture = windows.contains { window in
            !window.isMinimized
                && window.id < WindowEnumerator.syntheticIDBase
                && cache[window.id] == nil
        }

        var out = windows
        if !needsLiveCapture {
            for index in out.indices {
                let window = out[index]
                if window.isMinimized {
                    out[index].previewImage = placeholder(for: window)
                } else if let cached = cache[window.id] {
                    out[index].previewImage = cached
                } else {
                    out[index].previewImage = placeholder(for: window)
                }
            }
            return out
        }

        let maxDim = maxDimension
        let timeout = captureTimeout
        let uncachedIDs = Set(
            windows.filter { !$0.isMinimized && $0.id < WindowEnumerator.syntheticIDBase && cache[$0.id] == nil }
                .map(\.id)
        )

        let capturedCGImages: [CGWindowID: CGImage] = (try? await withTimeout(seconds: timeout) {
            let content = try await SCShareableContent.current
            let scMap: [CGWindowID: SCWindow] = Dictionary(
                content.windows.map { ($0.windowID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var images: [CGWindowID: CGImage] = [:]
            for windowID in uncachedIDs {
                guard let scWindow = scMap[windowID] else { continue }
                if let cgImage = await Self.captureCGImage(scWindow, maxDimension: maxDim) {
                    images[windowID] = cgImage
                }
            }
            return images
        }) ?? [:]

        for index in out.indices {
            let window = out[index]
            if window.isMinimized {
                out[index].previewImage = placeholder(for: window)
            } else if let cached = cache[window.id] {
                out[index].previewImage = cached
            } else if let cgImage = capturedCGImages[window.id] {
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                cache[window.id] = image
                out[index].previewImage = image
            } else {
                out[index].previewImage = placeholder(for: window)
            }
        }
        return out
    }

    // MARK: - Capturing

    private static func captureCGImage(_ window: SCWindow, maxDimension: CGFloat) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        let scale = min(1, maxDimension / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true

        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    // MARK: - Placeholder

    private func placeholder(for window: WindowInfo) -> NSImage {
        let size = NSSize(width: 320, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()

        // Background with rounded corners.
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor(white: 0.25, alpha: 1).setFill()
        path.fill()

        // App icon centered.
        if let icon = window.appIcon {
            let iconSize = NSSize(width: 96, height: 96)
            let iconRect = NSRect(
                x: (size.width - iconSize.width) / 2,
                y: (size.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            icon.draw(in: iconRect)
        }

        // "Minimized" badge at the bottom.
        if window.isMinimized {
            let text = String(localized: "Minimized") as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: (size.width - textSize.width) / 2, y: 16),
                withAttributes: attributes
            )
        }

        image.unlockFocus()
        return image
    }
}
