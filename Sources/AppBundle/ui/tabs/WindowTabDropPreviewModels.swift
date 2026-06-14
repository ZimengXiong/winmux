import CoreGraphics

struct WindowDropIntentOverlayModel: Equatable {
    let targetFrame: Rect
    let activeZone: WindowDropZone?
    let cornerRadius: CGFloat?

    static func == (lhs: WindowDropIntentOverlayModel, rhs: WindowDropIntentOverlayModel) -> Bool {
        lhs.targetFrame.topLeftX == rhs.targetFrame.topLeftX &&
            lhs.targetFrame.topLeftY == rhs.targetFrame.topLeftY &&
            lhs.targetFrame.width == rhs.targetFrame.width &&
            lhs.targetFrame.height == rhs.targetFrame.height &&
            lhs.activeZone == rhs.activeZone &&
            lhs.cornerRadius == rhs.cornerRadius
    }
}

enum WindowTabDropPreviewStyle: Equatable {
    case tabInsert
    case detach
    case stackSplit
    case swap
    case workspaceMove
    case sidebarWorkspaceMove
}

enum WindowTabDropPreviewGeometry: Equatable {
    case rounded
    case tabStrip
    case splitLeft
    case splitRight
    case splitAbove
    case splitBelow
}
