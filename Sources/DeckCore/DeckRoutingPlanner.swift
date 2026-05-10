import Foundation

public struct DeckRoutingSummary: Equatable, Sendable {
    public let routedWindowIds: [UInt32]
    public let operationsCount: Int

    public static let empty = DeckRoutingSummary(routedWindowIds: [], operationsCount: 0)
}

struct DeckRoutingPlanner {
    struct RoutedAction {
        let action: DeckAction
        let route: DeckRoute
    }

    static func plan(
        profile: DeckProfile,
        before: DeckAgentSnapshot?,
        after: DeckAgentSnapshot,
    ) -> ([DeckAgentOperation], DeckRoutingSummary) {
        let beforeIds = Set(before?.inventory.windows.map(\.windowId) ?? [])
        var assignedWindowIds: Set<UInt32> = []
        var groups: [RouteKey: [UInt32]] = [:]
        var focusByKey: [RouteKey: Bool] = [:]

        for action in profile.actions {
            guard let route = action.route else { continue }
            guard let match = action.effectiveMatch() else { continue }
            let key = RouteKey(workspace: route.workspace, tabGroup: route.tabGroup)
            focusByKey[key] = (focusByKey[key] ?? false) || route.focus

            let candidates = after.inventory.windows.filter { window in
                if assignedWindowIds.contains(window.windowId) { return false }
                if !route.reuseExisting && beforeIds.contains(window.windowId) { return false }
                return match.matches(window)
            }
            for window in candidates {
                assignedWindowIds.insert(window.windowId)
                groups[key, default: []].append(window.windowId)
            }
        }

        var operations: [DeckAgentOperation] = []
        for key in groups.keys.sorted() {
            let windowIds = groups[key, default: []]
            let shouldFocus = focusByKey[key] ?? false
            if key.tabGroup != nil, windowIds.count >= 2 {
                operations.append(.createTabGroup(
                    tabGroupId: nil,
                    workspace: key.workspace,
                    tabs: windowIds,
                    activeWindowId: shouldFocus ? windowIds.first : nil,
                ))
            } else if let workspace = key.workspace {
                for windowId in windowIds {
                    operations.append(.moveWindowToWorkspace(
                        windowId: windowId,
                        workspace: workspace,
                        focus: shouldFocus,
                    ))
                }
            }
        }

        return (
            operations,
            DeckRoutingSummary(
                routedWindowIds: Array(assignedWindowIds).sorted(),
                operationsCount: operations.count,
            )
        )
    }

    static func hasCandidateForEveryRoutedAction(
        profile: DeckProfile,
        before: DeckAgentSnapshot?,
        after: DeckAgentSnapshot,
    ) -> Bool {
        let routedActions = profile.actions.compactMap { action -> RoutedAction? in
            guard let route = action.route, action.effectiveMatch() != nil else { return nil }
            return RoutedAction(action: action, route: route)
        }
        guard !routedActions.isEmpty else { return true }

        let beforeIds = Set(before?.inventory.windows.map(\.windowId) ?? [])
        var assignedWindowIds: Set<UInt32> = []
        for routedAction in routedActions {
            guard let match = routedAction.action.effectiveMatch() else { return true }
            guard let window = after.inventory.windows.first(where: { window in
                if assignedWindowIds.contains(window.windowId) { return false }
                if !routedAction.route.reuseExisting && beforeIds.contains(window.windowId) { return false }
                return match.matches(window)
            }) else {
                return false
            }
            assignedWindowIds.insert(window.windowId)
        }
        return true
    }

    static func routableCandidateWindowIds(
        profile: DeckProfile,
        before: DeckAgentSnapshot?,
        after: DeckAgentSnapshot,
    ) -> Set<UInt32> {
        let beforeIds = Set(before?.inventory.windows.map(\.windowId) ?? [])
        var result: Set<UInt32> = []
        for action in profile.actions {
            guard let route = action.route,
                  let match = action.effectiveMatch()
            else {
                continue
            }
            for window in after.inventory.windows {
                if !route.reuseExisting && beforeIds.contains(window.windowId) { continue }
                if match.matches(window) {
                    result.insert(window.windowId)
                }
            }
        }
        return result
    }
}

private struct RouteKey: Hashable, Comparable {
    let workspace: String?
    let tabGroup: String?

    static func < (lhs: RouteKey, rhs: RouteKey) -> Bool {
        [lhs.workspace ?? "", lhs.tabGroup ?? ""].lexicographicallyPrecedes([rhs.workspace ?? "", rhs.tabGroup ?? ""])
    }
}

extension DeckWindowMatch {
    func matches(_ window: DeckAgentWindow) -> Bool {
        if let bundleId, window.appBundleId != bundleId { return false }
        if let appName, !matchesCaseInsensitive(window.appName, appName) { return false }
        if let titleEquals, !matchesCaseInsensitive(window.title, titleEquals) { return false }
        if let titleContains, !window.title.localizedCaseInsensitiveContains(titleContains) { return false }
        return true
    }
}

private func matchesCaseInsensitive(_ actual: String?, _ expected: String) -> Bool {
    actual?.caseInsensitiveCompare(expected) == .orderedSame
}
