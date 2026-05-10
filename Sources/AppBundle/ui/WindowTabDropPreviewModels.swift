import AppKit
import Common
import SwiftUI

struct WindowTabDropPreviewViewModel: Equatable {
    let containerFrame: CGRect
    let frame: CGRect
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
    let referenceWindowId: UInt32?
    let isPointerSettled: Bool
    let zones: [WindowTabDropPreviewZoneViewModel]
}

struct WindowTabDropPreviewZoneViewModel: Equatable {
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool
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

struct WindowIntentPreviewGuideLine: Equatable {
    let start: CGPoint
    let end: CGPoint
}

func windowIntentPreviewGuideLine(
    for geometry: WindowTabDropPreviewGeometry,
    in size: CGSize,
) -> WindowIntentPreviewGuideLine? {
    switch geometry {
        case .splitLeft:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: max(size.width - 1, 0), y: 8),
                end: CGPoint(x: max(size.width - 1, 0), y: max(size.height - 8, 8)),
            )
        case .splitRight:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 1, y: 8),
                end: CGPoint(x: 1, y: max(size.height - 8, 8)),
            )
        case .splitAbove:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 8, y: max(size.height - 1, 0)),
                end: CGPoint(x: max(size.width - 8, 8), y: max(size.height - 1, 0)),
            )
        case .splitBelow:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 8, y: 1),
                end: CGPoint(x: max(size.width - 8, 8), y: 1),
            )
        case .tabStrip:
            WindowIntentPreviewGuideLine(
                start: CGPoint(x: 10, y: max(size.height - 1, 1)),
                end: CGPoint(x: max(size.width - 10, 10), y: max(size.height - 1, 1)),
            )
        case .rounded:
            nil
    }
}

func windowIntentPreviewSymbolName(for style: WindowTabDropPreviewStyle, isGroup: Bool) -> String {
    switch style {
        case .tabInsert:
            "square.stack.3d.up"
        case .detach:
            "arrow.up.left.and.arrow.down.right"
        case .stackSplit:
            "rectangle.split.2x1"
        case .swap:
            "arrow.left.arrow.right"
        case .workspaceMove, .sidebarWorkspaceMove:
            isGroup ? "rectangle.stack.badge.plus" : "macwindow.badge.plus"
    }
}

