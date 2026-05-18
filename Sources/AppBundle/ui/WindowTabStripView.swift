import AppKit
import SwiftUI

struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel
    let drawsChrome: Bool

    @State var draggingTabId: UInt32?
    @State var hoveredTabId: UInt32?
    @State var dragTranslationX: CGFloat = 0
    @State var hasCommittedToDetach = false
    @State var pendingReorderDrop: WindowTabPendingReorderDrop?
    @State var tabScrollContentMinX: CGFloat = 0
    @Namespace var tabFeedbackNamespace
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            tabStripBody(
                stripWidth: max(proxy.size.width, 0),
                stripHeight: max(proxy.size.height, 0),
            )
        }
    }
}
