import AppKit

struct WindowDropIntentOverlayModel: Equatable {
    let targetFrame: CGRect
    let activeZone: WindowDropZone?
    let cornerRadius: CGFloat?
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
