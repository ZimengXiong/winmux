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

struct WindowTabStripScrollContentFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct WindowTabGroupHandleView: View {
    let windowId: UInt32?
    let workspaceName: String

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 10, height: 2)
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
