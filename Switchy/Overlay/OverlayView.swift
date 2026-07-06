//
//  Switchy
//  (c) 2026 Jan Gehring <jan@dunkel.tech>
//
//  This file is part of Switchy, licensed under the GNU Lesser General
//  Public License v3.0 (LGPLv3). See LICENSE.md for details.
//

import SwiftUI

/// Observable model for the overlay – populated by the `OverlayController`.
@MainActor
final class OverlayModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selectedIndex: Int = 0

    /// Called when an item is clicked (index).
    var onActivate: (Int) -> Void = { _ in }
    /// Called when the mouse hovers over an item (index).
    var onHover: (Int) -> Void = { _ in }
}

/// The horizontal preview bar. Shows a preview, the app icon and the (truncated)
/// title for each window.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private let itemWidth: CGFloat = 220
    private let itemHeight: CGFloat = 150

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                        item(for: window, isSelected: index == model.selectedIndex)
                            .id(index)
                            .onTapGesture { model.onActivate(index) }
                            .onHover { hovering in
                                if hovering { model.onHover(index) }
                            }
                    }
                }
                .padding(20)
            }
            .onChange(of: model.selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: itemHeight + 40 + 44)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func item(for window: WindowInfo, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                previewImage(for: window)
                    .frame(width: itemWidth, height: itemHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .padding(6)
                }
            }

            Text(window.displayTitle)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: itemWidth)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func previewImage(for window: WindowInfo) -> some View {
        if let preview = window.previewImage {
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.25))
        }
    }
}

/// Puts the native vibrant material (glassmorphism) behind the overlay.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
