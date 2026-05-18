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

    func cornerRadii(radius: CGFloat) -> PreviewCornerRadii {
        switch self {
            case .rounded:
                PreviewCornerRadii.uniform(radius)
            case .tabStrip:
                PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
            case .splitLeft:
                PreviewCornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
            case .splitRight:
                PreviewCornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
            case .splitAbove:
                PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
            case .splitBelow:
                PreviewCornerRadii(topLeft: 0, topRight: 0, bottomRight: radius, bottomLeft: radius)
        }
    }
}
