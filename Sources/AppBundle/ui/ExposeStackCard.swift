import AppKit
import SwiftUI

struct ExposeStackCard: View {
    let group: ExposeTabGroup
    let thumbnails: [UInt32: NSImage]
    let cw: CGFloat
    let ch: CGFloat
    @State private var hov = false

    private var activeIndex: Int {
        group.items.firstIndex(where: \.isFocused) ?? 0
    }

    var body: some View {
        let visibleItems = Array(group.items.prefix(4))
        let thumbH = ch - 24

        VStack(spacing: 4) {
            ZStack {
                ForEach(Array(visibleItems.enumerated().reversed()), id: \.element.id) { index, item in
                    exposeStackThumb(item: item, index: index, visibleCount: visibleItems.count, activeIndex: activeIndex, thumbH: thumbH)
                }
            }
            .frame(width: cw + 30, height: thumbH)
            .overlay(alignment: .bottomTrailing) {
                Text("\(group.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
                    .offset(x: 6, y: 6)
            }

            Text(group.items[safe: activeIndex]?.title ?? group.items.first?.title ?? "Group")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(hov ? 0.95 : 0.6))
                .lineLimit(1)
                .frame(maxWidth: cw)
        }
        .frame(width: cw + 30, height: ch)
        .contentShape(Rectangle())
        .onHover { hovering in
            hov = hovering
        }
        .animation(.easeOut(duration: 0.12), value: hov)
    }

    private func exposeStackThumb(
        item: ExposeWindowItem,
        index: Int,
        visibleCount: Int,
        activeIndex: Int,
        thumbH: CGFloat,
    ) -> some View {
        let isActive = index == activeIndex
        let depthIndex = abs(index - activeIndex)
        let cardW = cw - CGFloat(depthIndex) * 8
        let cardH = thumbH - CGFloat(depthIndex) * 4
        let itemWithThumbnail = item.withThumbnail(thumbnails[item.id])

        return exposeCardThumb(itemWithThumbnail, w: cardW, h: cardH, hov: isActive && hov)
            .offset(x: CGFloat(depthIndex) * 10, y: CGFloat(depthIndex) * 4)
            .rotation3DEffect(
                .degrees(Double(depthIndex) * -4),
                axis: (x: 0.15, y: 1.0, z: 0.0),
                anchor: .leading,
                perspective: 0.4
            )
            .opacity(isActive ? 1.0 : max(0.3, 1.0 - Double(depthIndex) * 0.25))
            .zIndex(Double(visibleCount - depthIndex))
    }
}
