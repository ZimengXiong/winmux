import Common

enum WindowStackSplitPosition: Equatable {
    case left
    case right
    case above
    case below

    var orientation: Orientation {
        switch self {
            case .left, .right: .h
            case .above, .below: .v
        }
    }

    var isPositive: Bool {
        switch self {
            case .right, .below: true
            case .left, .above: false
        }
    }

    var title: String {
        switch self {
            case .left: "Stack Left"
            case .right: "Stack Right"
            case .above: "Stack Above"
            case .below: "Stack Below"
        }
    }

    var subtitle: String {
        switch self {
            case .left: "Drop to split this tile and place the dragged item on the left"
            case .right: "Drop to split this tile and place the dragged item on the right"
            case .above: "Drop to split this tile and place the dragged item above"
            case .below: "Drop to split this tile and place the dragged item below"
        }
    }

    var previewGeometry: WindowTabDropPreviewGeometry {
        switch self {
            case .left: .splitLeft
            case .right: .splitRight
            case .above: .splitAbove
            case .below: .splitBelow
        }
    }
}
