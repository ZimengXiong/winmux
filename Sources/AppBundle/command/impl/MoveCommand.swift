import AppKit
import Common

struct MoveCommand: Command {
    let args: MoveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let currentNode = currentWindow.moveNode
        guard let parent = currentNode.parent else { return false }
        switch parent.cases {
            case .tilingContainer(let parent):
                let indexOfCurrent = currentNode.ownIndex.orDie()
                let indexOfSiblingTarget = indexOfCurrent + direction.focusOffset
                if parent.orientation == direction.orientation && parent.children.indices.contains(indexOfSiblingTarget) {
                    let siblingTarget = parent.children[indexOfSiblingTarget]
                    if currentNode is TilingContainer || (siblingTarget as? TilingContainer)?.layout == .accordion {
                        return moveNodeToSiblingIndex(currentNode, parent, indexOfSiblingTarget)
                    }
                    switch siblingTarget.tilingTreeNodeCasesOrDie() {
                        case .tilingContainer(let topLevelSiblingTargetContainer):
                            return deepMoveIn(node: currentNode, into: topLevelSiblingTargetContainer, moveDirection: direction)
                        case .window: // "swap windows"
                            return moveNodeToSiblingIndex(currentNode, parent, indexOfSiblingTarget)
                    }
                } else {
                    return moveOut(node: currentNode, direction: direction, io, args, env)
                }
            case .workspace: // floating window
                return io.err("moving floating windows isn't yet supported") // todo
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                return io.err(moveOutMacosUnconventionalWindow)
            case .macosPopupWindowsContainer:
                return false // Impossible
        }
    }
}

@MainActor
private func moveNodeToSiblingIndex(_ node: TreeNode, _ parent: TilingContainer, _ targetIndex: Int) -> Bool {
    let prevBinding = node.unbindFromParent()
    node.bind(to: parent, adaptiveWeight: prevBinding.adaptiveWeight, index: targetIndex)
    return true
}

@MainActor private func hitWorkspaceBoundaries(
    _ node: TreeNode,
    _ workspace: Workspace,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
    _ env: CmdEnv,
) -> Bool {
    switch args.boundaries {
        case .workspace:
            switch args.boundariesAction {
                case .stop: return true
                case .fail: return false
                case .createImplicitContainer:
                    createImplicitContainerAndMoveNode(node, workspace, direction)
                    return true
            }
        case .allMonitorsOuterFrame:
            guard let (monitors, index) = node.nodeMonitor?.findRelativeMonitor(inDirection: direction) else {
                return io.err("Should never happen. Can't find the current monitor")
            }

            if monitors.indices.contains(index) {
                let focusWindow = node.mostRecentWindowRecursive
                guard let focusWindow else { return false }
                let moveNodeToMonitorArgs = MoveNodeToMonitorCmdArgs(target: .direction(direction))
                    .copy(\.windowId, focusWindow.windowId)
                    .copy(\.focusFollowsWindow, focus.windowOrNil == focusWindow)

                return MoveNodeToMonitorCommand(args: moveNodeToMonitorArgs).run(env, io)
            } else {
                return hitAllMonitorsOuterFrameBoundaries(node, workspace, args, direction)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ node: TreeNode,
    _ workspace: Workspace,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
) -> Bool {
    switch args.boundariesAction {
        case .stop: return true
        case .fail: return false
        case .createImplicitContainer:
            createImplicitContainerAndMoveNode(node, workspace, direction)
            return true
    }
}

private let moveOutMacosUnconventionalWindow = "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"

@MainActor private func moveOut(
    node: TreeNode,
    direction: CardinalDirection,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ env: CmdEnv,
) -> Bool {
    let innerMostChild = node.parents.first(where: {
        return switch $0.parent?.cases {
            case .tilingContainer(let parent): parent.orientation == direction.orientation
            // Stop searching
            case .workspace, .macosMinimizedWindowsContainer, nil, .macosFullscreenWindowsContainer,
                 .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer: true
        }
    }) as? TilingContainer
    guard let innerMostChild else { return false }
    guard let parent = innerMostChild.parent else { return false }
    switch parent.cases {
        case .tilingContainer(let parent):
            check(parent.orientation == direction.orientation)
            guard let ownIndex = innerMostChild.ownIndex else { return false }
            node.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: ownIndex + direction.insertionOffset)
            return true
        case .workspace(let parent):
            return hitWorkspaceBoundaries(node, parent, io, args, direction, env)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            return io.err(moveOutMacosUnconventionalWindow)
        case .macosPopupWindowsContainer:
            return false // Impossible
    }
}

@MainActor private func createImplicitContainerAndMoveNode(
    _ node: TreeNode,
    _ workspace: Workspace,
    _ direction: CardinalDirection,
) {
    let prevRoot = workspace.rootTilingContainer
    prevRoot.unbindFromParent()
    // Force tiles layout
    _ = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, direction.orientation, .tiles, index: 0)
    check(prevRoot != workspace.rootTilingContainer)
    prevRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    node.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: direction.insertionOffset)
}

@MainActor private func deepMoveIn(node: TreeNode, into container: TilingContainer, moveDirection: CardinalDirection) -> Bool {
    let deepTarget = container.tilingTreeNodeCasesOrDie().findDeepMoveInTargetRecursive(moveDirection.orientation)
    switch deepTarget {
        case .tilingContainer(let deepTarget):
            node.bind(to: deepTarget, adaptiveWeight: WEIGHT_AUTO, index: 0)
        case .window(let deepTarget):
            guard let parent = deepTarget.parent as? TilingContainer else { return false }
            node.bind(
                to: parent,
                adaptiveWeight: WEIGHT_AUTO,
                index: deepTarget.ownIndex.orDie() + 1,
            )
    }
    return true
}

extension TilingTreeNodeCases {
    @MainActor fileprivate func findDeepMoveInTargetRecursive(_ orientation: Orientation) -> TilingTreeNodeCases {
        return switch self {
            case .window:
                self
            case .tilingContainer(let container):
                if container.orientation == orientation {
                    .tilingContainer(container)
                } else {
                    container.mostRecentChild.orDie("Empty containers must be detached during normalization")
                        .tilingTreeNodeCasesOrDie()
                        .findDeepMoveInTargetRecursive(orientation)
                }
        }
    }
}

extension Window {
    @MainActor
    var moveNode: TreeNode {
        if let parent = parent as? TilingContainer, parent.layout == .accordion {
            return parent
        } else {
            return self
        }
    }
}
