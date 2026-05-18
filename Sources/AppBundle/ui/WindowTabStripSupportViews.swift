import AppKit
import SwiftUI

struct WindowTabStripScrollFadeMask: View {
    let leadingFadeWidth: CGFloat
    let trailingFadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let leadingFade = min(leadingFadeWidth, proxy.size.width / 2)
            let trailingFade = min(trailingFadeWidth, proxy.size.width / 2)
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: leadingFade)
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: trailingFade)
            }
        }
    }
}

struct WindowTabStripScrollContentMinXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WindowTabGroupHandleView: View {
    let windowId: UInt32?
    let workspaceName: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Focus Tab Group")
        .frame(width: windowTabStripReservedGroupHandleWidth())
        .contentShape(Rectangle())
        .onTapGesture {
            guard let windowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(windowId, fallbackWorkspace: workspaceName)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .global)
                .onChanged { _ in
                    noteCurrentMousePointerSample()
                    guard let windowId,
                          shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                    else { return }
                    updateMoveFromTabStrip(windowId)
                }
                .onEnded { _ in
                    noteCurrentMousePointerSample()
                    guard let windowId,
                          shouldContinueCurrentGroupDrag(windowId: windowId)
                    else { return }
                    finishMoveFromTabStrip()
                },
        )
    }
}

struct WindowTabOcclusionMask: Shape {
    let panelFrame: CGRect
    let occludingScreenFrames: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for localRect in windowTabLocalOcclusionRects(
            panelFrame: panelFrame,
            occludingScreenFrames: occludingScreenFrames,
        ) {
            path.addRect(localRect)
        }
        return path
    }
}

extension View {
    func windowTabOcclusionMasked(panelFrame: CGRect, occludingScreenFrames: [CGRect]) -> some View {
        mask(
            WindowTabOcclusionMask(
                panelFrame: panelFrame,
                occludingScreenFrames: occludingScreenFrames,
            )
            .fill(style: FillStyle(eoFill: true))
        )
    }
}
