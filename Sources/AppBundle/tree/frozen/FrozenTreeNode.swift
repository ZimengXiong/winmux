import AppKit
import Common

enum FrozenTreeNode: Codable, Sendable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

struct FrozenContainer: Codable, Sendable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace,
                     .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    illegalChildParentRelation(child: $0, parent: container)
            }
        }
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
    }
}

struct FrozenWindow: Codable, Sendable {
    let id: UInt32
    let weight: CGFloat
    let isFullscreen: Bool
    let noOuterGapsInFullscreen: Bool
    let layoutReason: LayoutReason

    @MainActor init(_ window: Window) {
        id = window.windowId
        weight = getWeightOrNil(window) ?? 1
        isFullscreen = window.isFullscreen
        noOuterGapsInFullscreen = window.noOuterGapsInFullscreen
        layoutReason = window.layoutReason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case weight
        case isFullscreen
        case noOuterGapsInFullscreen
        case layoutReason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt32.self, forKey: .id)
        weight = try container.decode(CGFloat.self, forKey: .weight)
        isFullscreen = try container.decode(Bool.self, forKey: .isFullscreen)
        noOuterGapsInFullscreen = try container.decode(Bool.self, forKey: .noOuterGapsInFullscreen)
        layoutReason = try container.decodeIfPresent(LayoutReason.self, forKey: .layoutReason) ?? .standard
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}

extension FrozenTreeNode {
    private enum CodingKeys: String, CodingKey {
        case kind
        case container
        case window
    }

    private enum Kind: String, Codable {
        case container
        case window
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
            case .container:
                self = .container(try container.decode(FrozenContainer.self, forKey: .container))
            case .window:
                self = .window(try container.decode(FrozenWindow.self, forKey: .window))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .container(let frozenContainer):
                try container.encode(Kind.container, forKey: .kind)
                try container.encode(frozenContainer, forKey: .container)
            case .window(let frozenWindow):
                try container.encode(Kind.window, forKey: .kind)
                try container.encode(frozenWindow, forKey: .window)
        }
    }
}
