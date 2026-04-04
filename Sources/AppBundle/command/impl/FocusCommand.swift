import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        // todo bug: floating windows break mru
        let floatingWindows = args.floatingAsTiling ? try await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if args.floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { return false }
                    return windowToFocus.focusWindow()
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with ID \(windowId)")
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with DFS index \(dfsIndex)")
                }
            case .tabIndex(let tabIndex):
                guard let windowToFocus = tabWindowToFocus(target, tabIndex) else {
                    return io.err("Can't find tab with index \(tabIndex) in the current tab group")
                }
                return windowToFocus.focusWindow()
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return false
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return true
                        case .fail: return false
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return dieT("Must be discarded by args parser")
                    }
                }
                return windows[targetIndex].focusWindow()
            case .tabRelative(let nextPrev):
                return focusRelativeInCurrentTabGroup(target, args.boundariesAction, nextPrev)
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> Bool {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: true
                case .fail: false
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: dieT("Must be discarded by args parser")
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                return io.err("Should never happen. Can't find the current monitor")
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return targetMonitor.activeWorkspace.focusWorkspace()
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return false }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: Monitor,
) -> Bool {
    switch args.boundariesAction {
        case .stop:
            return true
        case .fail:
            return false
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return wrappedMonitor.activeWorkspace.focusWorkspace()
    }
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> Bool {
    guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
        return io.err(noWindowIsFocused)
    }
    return windowToFocus.focusWindow()
}

@MainActor private func focusRelativeInCurrentTabGroup(
    _ target: LiveFocus,
    _ boundariesAction: FocusCmdArgs.WhenBoundariesCrossed,
    _ nextPrev: TabNextPrev,
) -> Bool {
    guard
        let tabGroupData = currentTabGroupData(target)
    else {
        return switch boundariesAction {
            case .stop, .wrapAroundTheWorkspace: true
            case .fail: false
            case .wrapAroundAllMonitors: dieT("Must be discarded by args parser")
        }
    }
    let currentTab = tabGroupData.currentTab
    guard let currentIndex = currentTab.ownIndex else { return false }

    var targetIndex = currentIndex + nextPrev.focusOffset
    if !(0 ..< tabGroupData.group.children.count).contains(targetIndex) {
        switch boundariesAction {
            case .stop:
                return true
            case .fail:
                return false
            case .wrapAroundTheWorkspace:
                targetIndex = (targetIndex + tabGroupData.group.children.count) % tabGroupData.group.children.count
            case .wrapAroundAllMonitors:
                return dieT("Must be discarded by args parser")
        }
    }

    return tabWindowToFocus(tabGroupData.group, targetIndex).map { $0.focusWindow() } ?? false
}

@MainActor
private func tabWindowToFocus(_ target: LiveFocus, _ oneBasedTabIndex: UInt32) -> Window? {
    guard let group = currentTabGroupData(target)?.group else { return nil }
    return tabWindowToFocus(group, Int(oneBasedTabIndex) - 1)
}

@MainActor
private func tabWindowToFocus(_ group: TilingContainer, _ zeroBasedIndex: Int) -> Window? {
    guard let targetTab = group.children.getOrNil(atIndex: zeroBasedIndex) else { return nil }
    return targetTab.mostRecentWorkspaceFocusableWindowRecursive ?? targetTab.tabRepresentativeWindow
}

@MainActor
private func currentTabGroupData(_ target: LiveFocus) -> (group: TilingContainer, currentTab: TreeNode)? {
    guard
        let focusedWindow = target.windowOrNil,
        let tabGroup = focusedWindow.nearestWindowTabGroup,
        let currentTab = focusedWindow.directChild(in: tabGroup)
    else { return nil }
    return (tabGroup, currentTab)
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async throws -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var _floatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        let center = try await window.getCenter() // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findIn(tree: workspace.rootTilingContainer, virtual: true)
        {
            guard let targetCenter = try await target.getCenter() else { continue }
            guard let _tilingParent = target.parent as? TilingContainer else { continue }
            tilingParent = _tilingParent
            index = center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                ? target.ownIndex.orDie() + 1
                : target.ownIndex.orDie()
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        let data = window.unbindFromParent()
        let floatingWindowData = FloatingWindowData(
            window: window,
            center: center,
            parent: tilingParent,
            adaptiveWeight: data.adaptiveWeight,
            index: index,
        )
        _floatingWindows.append(floatingWindowData)
    }
    let floatingWindows: [FloatingWindowData] = _floatingWindows.sortedBy { $0.center.getProjection($0.parent.orientation) }.reversed()

    for floating in floatingWindows { // Make floating windows be seen as tiling
        floating.window.bind(to: floating.parent, adaptiveWeight: 1, index: floating.index)
    }
    return floatingWindows
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let parent: TilingContainer
    let adaptiveWeight: CGFloat
    let index: Int
}

extension TreeNode {
    @MainActor
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findLeafWindowRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                die("Impossible")
        }
    }
}
