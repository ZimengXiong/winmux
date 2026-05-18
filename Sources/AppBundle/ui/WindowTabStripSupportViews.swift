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
        Button {
            guard let windowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(windowId, fallbackWorkspace: workspaceName)
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus Tab Group")
        .frame(width: windowTabStripReservedGroupHandleWidth())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    guard let windowId else { return }
                    updateMoveFromTabStrip(windowId)
                }
                .onEnded { _ in
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
