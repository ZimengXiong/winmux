import Common
import Foundation

@MainActor
func currentAgentWorldId() -> String {
    let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).sortedBy(\.name)
    var lines: [String] = []
    for workspace in workspaces {
        lines += agentWorldLines(for: workspace)
    }
    for window in macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self).sortedBy(\.windowId) {
        lines.append(agentMinimizedWorldLine(for: window))
    }
    return stableAgentHash(lines.joined(separator: "\n"))
}

@MainActor
private func agentWorldLines(for workspace: Workspace) -> [String] {
    var lines = ["workspace|\(workspace.name)|visible:\(workspace.isVisible)|monitor:\(workspace.workspaceMonitor.monitorId_oneBased?.description ?? "nil")"]
    lines.append(contentsOf: workspace.rootTilingContainer.agentWorldLines(prefix: "tree|\(workspace.name)"))
    for window in workspace.allLeafWindowsRecursive.sortedBy(\.windowId) {
        lines.append(agentWorldLine(for: window))
    }
    for group in workspace.rootTilingContainer.allAgentTabGroupsRecursive.sortedBy({ agentTabGroupId($0) }) {
        lines.append(agentWorldLine(for: group))
    }
    return lines
}

@MainActor
private func agentWorldLine(for window: Window) -> String {
    [
        "window",
        window.windowId.description,
        window.nodeWorkspace?.name ?? "nil",
        window.agentPaneId ?? "nil",
        window.nearestWindowTabGroup.map(agentTabGroupId) ?? "nil",
        window.agentLayoutDescription,
        "fullscreen:\(window.isFullscreen)",
        "noOuterGaps:\(window.noOuterGapsInFullscreen)",
    ].joined(separator: "|")
}

@MainActor
private func agentMinimizedWorldLine(for window: Window) -> String {
    let origin = switch window.layoutReason {
        case .standard: "standard"
        case .macos(let previousParentKind, let previousWorkspaceName):
            "\(previousParentKind.rawValue):\(previousWorkspaceName ?? "nil")"
    }
    return agentWorldLine(for: window) + "|origin:\(origin)"
}

@MainActor
private func agentWorldLine(for group: TilingContainer) -> String {
    [
        "tabGroup",
        agentTabGroupId(group),
        group.nodeWorkspace?.name ?? "nil",
        "active:\(group.tabActiveWindow?.windowId.description ?? "nil")",
        "tabs:\(group.agentTabWindows.map(\.windowId).map(String.init).joined(separator: ","))",
    ].joined(separator: "|")
}

func stableAgentHash(_ input: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in input.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

func duplicateAgentWindowIds(in ids: [UInt32]) -> [UInt32] {
    var seen: Set<UInt32> = []
    var duplicates: Set<UInt32> = []
    for id in ids where !seen.insert(id).inserted {
        duplicates.insert(id)
    }
    return duplicates.sorted()
}
