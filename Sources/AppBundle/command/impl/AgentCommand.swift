import AppKit
import Common
import Foundation

struct AgentCommand: Command {
    let args: AgentCmdArgs
    var shouldResetClosedWindowsCache: Bool { args.subcommand.val == .apply }
    var canSkipPostCommandRefresh: Bool { args.subcommand.val != .apply }

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        switch args.subcommand.val {
            case .query:
                let snapshot = try await AgentSnapshot.query()
                guard let json = JSONEncoder.winMuxDefault.encodeToString(snapshot) else {
                    return io.err("Failed to encode agent snapshot")
                }
                if let path = args.path {
                    try json.write(to: URL(filePath: path), atomically: true, encoding: .utf8)
                    return true
                }
                return io.out(json)
            case .check:
                let request: AgentRequest
                do {
                    request = try AgentRequest.read(path: args.path.orDie())
                } catch {
                    return io.err("Failed to read agent JSON: \(describeAgentJsonError(error))")
                }
                let errors = try await request.validate()
                if errors.isEmpty {
                    return io.out("OK")
                }
                return io.err(errors.joinErrors())
            case .apply:
                let request: AgentRequest
                do {
                    request = try AgentRequest.read(path: args.path.orDie())
                } catch {
                    return io.err("Failed to read agent JSON: \(describeAgentJsonError(error))")
                }
                let errors = try await request.validate()
                if !errors.isEmpty {
                    return io.err(errors.joinErrors())
                }
                try await request.apply()
                return true
            case .skill:
                return io.out(agentSkillText)
        }
    }
}

private func describeAgentJsonError(_ error: Error) -> String {
    func path(_ codingPath: [any CodingKey]) -> String {
        let result = codingPath.map(\.stringValue).joined(separator: ".")
        return result.isEmpty ? "<root>" : result
    }
    switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.typeMismatch(_, let context):
            return "type mismatch at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.valueNotFound(_, let context):
            return "missing value at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            return "invalid data at \(path(context.codingPath)): \(context.debugDescription)"
        default:
            return error.localizedDescription
    }
}

private let agentSkillText = """
    ---
    name: winmux-agent
    description: Use when arranging WinMux windows through the agent JSON interface. Query to a file, read that exact file, edit it, then apply that exact file.
    ---

    # WinMux Agent

    You MUST use the file workflow. Do not guess operation names. Do not search the repository for docs. This skill is the command reference.

    Required workflow for every user request:
    1. Query the current state into a JSON file:
       `winmux agent query --path /tmp/winmux-agent.json`
    2. Read the file you just wrote:
       `/tmp/winmux-agent.json`
       Important: `query --path` writes the JSON to the path. It does not print the JSON to stdout. Running `ls /tmp/winmux-agent.json` is not enough; you must read the file contents.
    3. Edit only the `edit` object inside `/tmp/winmux-agent.json`.
       Treat `schemaVersion`, `snapshotId`, `worldId`, `inventory`, and `reasoning` as read-only context. Do not edit titles, app names, frames, panes, workspace inventory, or the world id.
    4. For a small change, replace the entire `edit.operations` array with only the operations for the current user request. Do not append to operations left by an earlier request.
    5. For a full workspace redesign, edit `edit.layout.workspaces` instead of `edit.operations`.
    6. Apply the same file:
       `winmux agent apply --path /tmp/winmux-agent.json`
    7. If apply says the JSON is stale or the `worldId` does not match, discard `/tmp/winmux-agent.json`, run the query command again, read the new file, redo the edit, and apply again.
    8. Return a short summary of what changed.

    Usually skip the separate check command. `apply` validates before changing anything. Use `winmux agent check --path /tmp/winmux-agent.json` only for complex edits or after a failed apply.

    The file includes a `worldId` freshness guard. If windows move, close, change fullscreen state, or the user manually changes the layout, discard the file and query again.

    For small changes, replace the entire `edit.operations` array. Do not append to old operations unless the user asked for one multi-step batch. Prefer operations for focus, moving one window, moving one tab group, swapping, placing one pane, setting WinMux fullscreen, closing, or parking windows.

    For full workspace setup, edit `edit.layout.workspaces`. Use layout mode for requests like "set up my coding workspace" or "organize all windows into workspaces".

    Use `windowId` for one window. Use `tabGroupId` for the whole tab group. If the user says "tab group", "tabs", "tap group", or "the whole group", do not move only the active window. `createTabGroup` takes `tabs`; `windows` is accepted as an alias.

    If the user says "all Chrome windows" or "all IDEs", scan every item in `inventory.windows` and include every matching `windowId`. Do not stop after the first match. Also inspect `inventory.tabGroups`, because an existing tab group may already contain more matching windows.

    If you create a tab group in `edit.operations` and need to refer to it later in the same operations array, give it a temporary `tabGroupId` and reuse that exact value later. Example: create with `"tabGroupId": "tabgroup-chrome"` and then refer to `{ "tabGroupId": "tabgroup-chrome" }`. The alias is only for the current apply; after applying, query again to see the real persistent tab group id.

    Read the query file before choosing IDs:
    - Find windows in `inventory.windows`. Match by `appName`, `title`, and `windowId`.
    - Find whole tab groups in `inventory.tabGroups`. Use `tabGroupId` when moving or editing the whole group.
    - Find current layout in `reasoning.panes`, `reasoning.relations`, and `reasoning.rawTrees`.
    - Use `size` and `sizeAxis` from the query file to understand current proportions before resizing.
    - Never invent a `windowId`, `paneId`, `tabGroupId`, or workspace name if the query file already gives the correct value.

    Canonical operation type names are camelCase. Common snake_case aliases are accepted, but prefer the exact schemas below.

    Pane refs:
    - Window: `{ "windowId": 123 }` or pane id `"pane-123"`
    - Tab group: `{ "tabGroupId": "tabgroup-123" }` or pane id `"pane-tabgroup-123"`

    All `edit.operations` commands:
    - `focusWindow`: `{ "type": "focusWindow", "windowId": 123 }`
    - `focusWindow` by match: `{ "type": "focusWindow", "match": { "appName": "Google Chrome", "titleContains": "Docs" } }`
    - `focusWorkspace`: `{ "type": "focusWorkspace", "workspace": "2" }`
    - `moveWindowToWorkspace`: `{ "type": "moveWindowToWorkspace", "windowId": 123, "workspace": "2", "focus": true }`
    - `moveTabGroupToWorkspace`: `{ "type": "moveTabGroupToWorkspace", "tabGroupId": "tabgroup-123", "workspace": "2", "focus": true }`
    - `swapPanes`: `{ "type": "swapPanes", "paneId1": "pane-123", "paneId2": "pane-456" }`
    - `swapPanes` alt: `{ "type": "swapPanes", "a": { "windowId": 123 }, "b": { "tabGroupId": "tabgroup-456" } }`
    - `placePane`: `{ "type": "placePane", "pane": { "windowId": 123 }, "relation": "below", "target": { "windowId": 456 } }`
    - `createTabGroup`: `{ "type": "createTabGroup", "tabGroupId": "tabgroup-chrome", "workspace": "1", "tabs": [123, 456, 789], "activeWindowId": 123 }`
    - `createTabGroup` alt: `{ "type": "createTabGroup", "tabGroupId": "tabgroup-chrome", "windows": [123, 456, 789] }`
    - `addWindowToTabGroup`: `{ "type": "addWindowToTabGroup", "windowId": 123, "tabGroupId": "tabgroup-456", "activeWindowId": 123 }`
    - `moveWindowOutOfTabGroup`: `{ "type": "moveWindowOutOfTabGroup", "windowId": 123 }`
    - `setActiveTab`: `{ "type": "setActiveTab", "tabGroupId": "tabgroup-123", "windowId": 456 }`
    - `setWinMuxFullscreen`: `{ "type": "setWinMuxFullscreen", "windowId": 123, "value": true, "noOuterGaps": true }`
    - `setFloating`: `{ "type": "setFloating", "windowId": 123, "value": true }`
    - `closeWindow`: `{ "type": "closeWindow", "windowId": 123, "quitAppIfLastWindow": true }`
    - `parkWindow`: `{ "type": "parkWindow", "pane": { "windowId": 123 }, "workspace": "__agent_parked" }`
    - `setPaneSize`: `{ "type": "setPaneSize", "pane": { "windowId": 123 }, "size": 0.8 }`
    - `setPaneSize` percent alt: `{ "type": "setPaneSize", "pane": { "tabGroupId": "tabgroup-123" }, "sizePercent": 80 }`
    - `setPaneSize` vertical split: `{ "type": "setPaneSize", "pane": { "windowId": 123 }, "axis": "vertical", "size": 0.75 }`
    - `setWorkspaceLayout`: `{ "type": "setWorkspaceLayout", "layout": { "name": "1", "layout": { "kind": "window", "windowId": 123 } } }`

    For a small change, the `edit` object in the queried file should look like this. Keep the rest of the queried file unchanged:
    ```json
    {
      "edit": {
        "operations": [
          { "type": "focusWindow", "windowId": 123 }
        ]
      }
    }
    ```

    Relations for `placePane`: `leftOf`, `rightOf`, `above`, `below`.

    WinMux fullscreen is not macOS native fullscreen. Use `setWinMuxFullscreen`.

    If the user wants a window not to show in the current workspace but does not ask to close it, use `parkWindow` or `moveWindowToWorkspace`, not native minimize.

    Full layout mode:
    - Edit `edit.layout.workspaces`.
    - Replace `edit.operations` with an empty array unless the user explicitly asked for extra operations in the same batch.
    - Prefer layout mode when the user asks to design or reorganize a workspace, especially when the request includes exact sizes like "80/20", "left takes 80%", or multiple groups/panes in one workspace.
    - A split's `direction` describes how children are arranged: `horizontal` means left/right; `vertical` means top/bottom.
    - Workspace layout shape: `{ "name": "coding", "layout": <layoutNode>, "focus": { "windowId": 123 }, "floating": [{ "windowId": 456 }] }`
    - Split node: `{ "kind": "split", "direction": "horizontal", "children": [<layoutNode>, <layoutNode>], "size": 0.5 }`
    - Window node: `{ "kind": "window", "windowId": 123, "size": 0.5 }`
    - Tab group node: `{ "kind": "tabGroup", "tabs": [123, 456], "activeWindowId": 123, "size": 0.5 }`
    - Directions: `horizontal`, `vertical`.
    - `size` is a proportional share of the parent split. Use `0.8` for 80%. `80` and `sizePercent: 80` are also accepted. If a sibling omits `size`, it receives an equal share of the remaining space.
    - For `setPaneSize`, add `"axis": "vertical"` when resizing a top/bottom split and `"axis": "horizontal"` when resizing a left/right split. Without `axis`, WinMux uses the nearest split containing the pane.
    - For "Chrome 80%, IDE column 20%, terminal below IDE", use a horizontal root split with Chrome tab group `size: 0.8` and a vertical split `size: 0.2` containing the IDE tab group and terminal.

    For a full layout redesign, the `edit` object in the queried file should look like this. Keep the rest of the queried file unchanged:
    ```json
    {
      "edit": {
        "layout": {
          "workspaces": [
            {
              "name": "1",
              "layout": {
                "kind": "split",
                "direction": "horizontal",
                "children": [
                  { "kind": "window", "windowId": 123, "size": 0.8 },
                  { "kind": "window", "windowId": 456, "size": 0.2 }
                ]
              },
              "focus": { "windowId": 123 }
            }
          ]
        }
      }
    }
    ```
    """

// MARK: - Query

struct AgentSnapshot: Encodable {
    let schemaVersion: Int
    let snapshotId: String
    let worldId: String
    let inventory: AgentInventory
    let reasoning: AgentReasoning
    let edit: AgentEditTemplate

    @MainActor
    static func query() async throws -> AgentSnapshot {
        let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
        var windows: [AgentWindowInfo] = []
        var tabGroups: [AgentTabGroupInfo] = []
        var workspaceInfos: [AgentWorkspaceInfo] = []
        var allPanes: [AgentPaneInfo] = []
        var allRelations: [AgentPaneRelation] = []
        var rawTrees: [AgentRawWorkspaceTree] = []

        for workspace in workspaces {
            let panes = workspace.agentPaneInfos()
            let relations = workspace.agentPaneRelations()
            allPanes.append(contentsOf: panes)
            allRelations.append(contentsOf: relations)
            rawTrees.append(AgentRawWorkspaceTree(workspace: workspace.name, tree: workspace.rootTilingContainer.agentRawLayoutNode()))
            workspaceInfos.append(AgentWorkspaceInfo(
                name: workspace.name,
                displayName: workspaceDisplayName(workspace.name),
                visible: workspace.isVisible,
                focused: focus.workspace == workspace,
                monitorId: workspace.workspaceMonitor.monitorId_oneBased,
                panes: panes.map(\.paneId),
            ))
            for group in workspace.rootTilingContainer.allAgentTabGroupsRecursive {
                tabGroups.append(await AgentTabGroupInfo(group))
            }
            for window in workspace.allLeafWindowsRecursive {
                windows.append(try await AgentWindowInfo(window))
            }
        }

        let inventory = AgentInventory(
            windows: windows.sortedBy(\.windowId),
            tabGroups: tabGroups.sortedBy(\.tabGroupId),
            workspaces: workspaceInfos.sortedBy(\.name),
        )
        let reasoning = AgentReasoning(
            panes: allPanes.sortedBy(\.paneId),
            relations: allRelations.sortedBy([{ $0.workspace }, { $0.paneId }]),
            rawTrees: rawTrees.sortedBy(\.workspace),
        )
        return AgentSnapshot(
            schemaVersion: 1,
            snapshotId: ISO8601DateFormatter().string(from: Date()),
            worldId: currentAgentWorldId(),
            inventory: inventory,
            reasoning: reasoning,
            edit: AgentEditTemplate(operations: [], layout: nil),
        )
    }
}

struct AgentInventory: Encodable {
    let windows: [AgentWindowInfo]
    let tabGroups: [AgentTabGroupInfo]
    let workspaces: [AgentWorkspaceInfo]
}

struct AgentWorkspaceInfo: Encodable {
    let name: String
    let displayName: String
    let visible: Bool
    let focused: Bool
    let monitorId: Int?
    let panes: [String]
}

struct AgentWindowInfo: Encodable {
    let windowId: UInt32
    let title: String
    let appName: String?
    let appBundleId: String?
    let pid: Int32
    let workspace: String?
    let paneId: String?
    let tabGroupId: String?
    let focused: Bool
    let winMuxFullscreen: Bool
    let noOuterGapsInFullscreen: Bool
    let layout: String
    let size: CGFloat?
    let sizeAxis: AgentLayoutDirection?
    let frame: AgentRect?

    @MainActor
    init(_ window: Window) async throws {
        windowId = window.windowId
        title = try await window.title
        appName = window.app.name
        appBundleId = window.app.rawAppBundleId
        pid = window.app.pid
        workspace = window.nodeWorkspace?.name
        tabGroupId = window.nearestWindowTabGroup.map(agentTabGroupId)
        paneId = window.agentPaneId
        focused = focus.windowOrNil == window
        winMuxFullscreen = window.isFullscreen
        noOuterGapsInFullscreen = window.noOuterGapsInFullscreen
        layout = window.agentLayoutDescription
        let sizingNode = window.agentPaneSizingNode
        size = sizingNode.agentSizeRatio
        sizeAxis = sizingNode.agentSizeAxis
        frame = (window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect).map(AgentRect.init)
    }
}

struct AgentTabGroupInfo: Encodable {
    let tabGroupId: String
    let paneId: String
    let workspace: String?
    let activeWindowId: UInt32?
    let tabs: [UInt32]
    let tabTitles: [String]
    let size: CGFloat?
    let sizeAxis: AgentLayoutDirection?
    let frame: AgentRect?

    @MainActor
    init(_ group: TilingContainer) async {
        tabGroupId = agentTabGroupId(group)
        paneId = agentPaneIdForTabGroup(tabGroupId: tabGroupId)
        workspace = group.nodeWorkspace?.name
        activeWindowId = group.tabActiveWindow?.windowId
        let windows = group.agentTabWindows
        tabs = windows.map(\.windowId)
        var titles: [String] = []
        for window in windows {
            titles.append((try? await window.title) ?? "")
        }
        tabTitles = titles
        size = group.agentSizeRatio
        sizeAxis = group.agentSizeAxis
        frame = (group.lastAppliedLayoutPhysicalRect ?? group.lastAppliedLayoutVirtualRect).map(AgentRect.init)
    }
}

struct AgentReasoning: Encodable {
    let panes: [AgentPaneInfo]
    let relations: [AgentPaneRelation]
    let rawTrees: [AgentRawWorkspaceTree]
}

struct AgentPaneInfo: Encodable {
    let paneId: String
    let kind: AgentPaneKind
    let workspace: String
    let windowId: UInt32?
    let tabGroupId: String?
    let label: String
    let size: CGFloat?
    let sizeAxis: AgentLayoutDirection?
    let frame: AgentRect?
}

enum AgentPaneKind: String, Codable {
    case window
    case tabGroup
}

struct AgentPaneRelation: Encodable {
    let workspace: String
    let paneId: String
    var left: String?
    var right: String?
    var above: String?
    var below: String?
}

struct AgentRawWorkspaceTree: Encodable {
    let workspace: String
    let tree: AgentRawLayoutNode
}

indirect enum AgentRawLayoutNode: Encodable {
    case split(direction: AgentLayoutDirection, layout: String, size: CGFloat?, children: [AgentRawLayoutNode])
    case window(windowId: UInt32, size: CGFloat?)
    case tabGroup(tabGroupId: String, activeWindowId: UInt32?, tabs: [UInt32], size: CGFloat?)

    enum CodingKeys: String, CodingKey {
        case kind
        case direction
        case layout
        case size
        case children
        case windowId
        case tabGroupId
        case activeWindowId
        case tabs
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .split(let direction, let layout, let size, let children):
                try container.encode("split", forKey: .kind)
                try container.encode(direction, forKey: .direction)
                try container.encode(layout, forKey: .layout)
                try container.encodeIfPresent(size, forKey: .size)
                try container.encode(children, forKey: .children)
            case .window(let windowId, let size):
                try container.encode("window", forKey: .kind)
                try container.encode(windowId, forKey: .windowId)
                try container.encodeIfPresent(size, forKey: .size)
            case .tabGroup(let tabGroupId, let activeWindowId, let tabs, let size):
                try container.encode("tabGroup", forKey: .kind)
                try container.encode(tabGroupId, forKey: .tabGroupId)
                try container.encode(activeWindowId, forKey: .activeWindowId)
                try container.encode(tabs, forKey: .tabs)
                try container.encodeIfPresent(size, forKey: .size)
        }
    }
}

struct AgentRect: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: Rect) {
        x = rect.topLeftX
        y = rect.topLeftY
        width = rect.width
        height = rect.height
    }
}

struct AgentEditTemplate: Encodable {
    let operations: [String]
    let layout: AgentLayoutEdit?
}

// MARK: - Input

struct AgentRequest: Decodable {
    let schemaVersion: Int?
    let snapshotId: String?
    let worldId: String?
    let edit: AgentEdit?

    static func read(path: String) throws -> AgentRequest {
        let data = try Data(contentsOf: URL(filePath: path))
        return try JSONDecoder().decode(AgentRequest.self, from: data)
    }

    var operations: [AgentOperation] {
        (edit?.operations ?? []) + (edit?.actions ?? [])
    }

    @MainActor
    func validate() async throws -> [String] {
        var errors: [String] = []
        validateFreshWorldId(appendTo: &errors)
        guard errors.isEmpty else { return errors }
        var context = AgentValidationContext()
        for operation in operations {
            try await operation.validate(context: &context, appendTo: &errors)
        }
        if let layout = edit?.layout {
            try await layout.validate(appendTo: &errors)
        }
        return errors
    }

    @MainActor
    private func validateFreshWorldId(appendTo errors: inout [String]) {
        if let worldId {
            let currentWorldId = currentAgentWorldId()
            if worldId != currentWorldId {
                errors.append("Agent JSON is stale: worldId '\(worldId)' does not match current worldId '\(currentWorldId)'. Run 'winmux agent query --path <path>' again before applying.")
            }
        } else if snapshotId != nil {
            errors.append("Agent JSON is missing worldId. Run 'winmux agent query --path <path>' again before applying.")
        }
    }

    @MainActor
    func apply() async throws {
        var context = AgentApplyContext()
        for operation in operations {
            try await operation.apply(context: &context)
        }
        if let layout = edit?.layout {
            try await layout.apply()
        }
    }
}

struct AgentEdit: Decodable {
    let mode: String?
    let operations: [AgentOperation]?
    let actions: [AgentOperation]?
    let layout: AgentLayoutEdit?
}

private struct AgentValidationContext {
    var plannedTabGroups: [String: Set<UInt32>] = [:]
}

private struct AgentApplyContext {
    var tabGroupAliases: [String: TilingContainer] = [:]
}

struct AgentLayoutEdit: Codable {
    let workspaces: [AgentWorkspaceLayout]

    @MainActor
    func validate(appendTo errors: inout [String]) async throws {
        for workspace in workspaces {
            try await workspace.validate(appendTo: &errors)
        }
    }

    @MainActor
    func apply() async throws {
        for workspace in workspaces {
            try await workspace.apply()
        }
    }
}

// MARK: - Operations

enum AgentOperation: Decodable {
    case focusWindow(AgentWindowTarget)
    case focusWorkspace(workspace: String)
    case moveWindowToWorkspace(windowId: UInt32, workspace: String, focus: Bool?)
    case moveTabGroupToWorkspace(tabGroupId: String, workspace: String, focus: Bool?)
    case swapPanes(a: AgentPaneRef, b: AgentPaneRef)
    case placePane(pane: AgentPaneRef, relation: AgentPaneRelationKind, target: AgentPaneRef)
    case createTabGroup(tabGroupId: String?, workspace: String?, tabs: [UInt32], activeWindowId: UInt32?)
    case addWindowToTabGroup(windowId: UInt32, tabGroupId: String, activeWindowId: UInt32?)
    case moveWindowOutOfTabGroup(windowId: UInt32)
    case setActiveTab(tabGroupId: String, windowId: UInt32)
    case setWinMuxFullscreen(windowId: UInt32, value: Bool, noOuterGaps: Bool?)
    case setFloating(windowId: UInt32, value: Bool)
    case closeWindow(windowId: UInt32, quitAppIfLastWindow: Bool?)
    case parkWindow(AgentPaneRef, workspace: String?)
    case setPaneSize(pane: AgentPaneRef, axis: AgentLayoutDirection?, size: CGFloat)
    case setWorkspaceLayout(AgentWorkspaceLayout)

    enum CodingKeys: String, CodingKey {
        case type
        case workspace
        case windowId
        case windowId1
        case windowId2
        case tabGroupId
        case focus
        case a
        case b
        case pane
        case paneId1
        case paneId2
        case relation
        case target
        case tabs
        case windows
        case activeWindowId
        case value
        case noOuterGaps
        case quitAppIfLastWindow
        case axis
        case direction
        case size
        case sizePercent
        case layout
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)
        switch normalizedAgentOperationType(rawType) {
            case "focuswindow":
                self = .focusWindow(try AgentWindowTarget(from: decoder))
            case "focusworkspace":
                self = .focusWorkspace(workspace: try container.decode(String.self, forKey: .workspace))
            case "movewindowtoworkspace":
                self = .moveWindowToWorkspace(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    workspace: try container.decode(String.self, forKey: .workspace),
                    focus: try container.decodeIfPresent(Bool.self, forKey: .focus),
                )
            case "movetabgrouptoworkspace":
                self = .moveTabGroupToWorkspace(
                    tabGroupId: try container.decode(String.self, forKey: .tabGroupId),
                    workspace: try container.decode(String.self, forKey: .workspace),
                    focus: try container.decodeIfPresent(Bool.self, forKey: .focus),
                )
            case "swappanes", "swap", "swapwindows":
                self = .swapPanes(
                    a: try container.decodeAgentPaneRef(primaryKey: .a, paneIdKey: .paneId1, windowIdKey: .windowId1),
                    b: try container.decodeAgentPaneRef(primaryKey: .b, paneIdKey: .paneId2, windowIdKey: .windowId2),
                )
            case "placepane":
                self = .placePane(
                    pane: try container.decode(AgentPaneRef.self, forKey: .pane),
                    relation: try container.decode(AgentPaneRelationKind.self, forKey: .relation),
                    target: try container.decode(AgentPaneRef.self, forKey: .target),
                )
            case "createtabgroup":
                self = .createTabGroup(
                    tabGroupId: try container.decodeIfPresent(String.self, forKey: .tabGroupId),
                    workspace: try container.decodeIfPresent(String.self, forKey: .workspace),
                    tabs: try container.decodeWindowIdArray(primaryKey: .tabs, aliasKey: .windows),
                    activeWindowId: try container.decodeIfPresent(UInt32.self, forKey: .activeWindowId),
                )
            case "addwindowtotabgroup":
                self = .addWindowToTabGroup(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    tabGroupId: try container.decode(String.self, forKey: .tabGroupId),
                    activeWindowId: try container.decodeIfPresent(UInt32.self, forKey: .activeWindowId),
                )
            case "movewindowoutoftabgroup":
                self = .moveWindowOutOfTabGroup(windowId: try container.decode(UInt32.self, forKey: .windowId))
            case "setactivetab":
                self = .setActiveTab(
                    tabGroupId: try container.decode(String.self, forKey: .tabGroupId),
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                )
            case "setwinmuxfullscreen", "setfullscreen":
                self = .setWinMuxFullscreen(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    value: try container.decode(Bool.self, forKey: .value),
                    noOuterGaps: try container.decodeIfPresent(Bool.self, forKey: .noOuterGaps),
                )
            case "setfloating":
                self = .setFloating(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    value: try container.decode(Bool.self, forKey: .value),
                )
            case "closewindow":
                self = .closeWindow(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    quitAppIfLastWindow: try container.decodeIfPresent(Bool.self, forKey: .quitAppIfLastWindow),
                )
            case "parkwindow":
                self = .parkWindow(
                    try container.decode(AgentPaneRef.self, forKey: .pane),
                    workspace: try container.decodeIfPresent(String.self, forKey: .workspace),
                )
            case "setpanesize", "resizepane":
                self = .setPaneSize(
                    pane: try container.decode(AgentPaneRef.self, forKey: .pane),
                    axis: try container.decodeAgentSizeAxis(axisKey: .axis, directionKey: .direction),
                    size: try container.decodeAgentSizeRatio(sizeKey: .size, percentKey: .sizePercent),
                )
            case "setworkspacelayout":
                self = .setWorkspaceLayout(try container.decode(AgentWorkspaceLayout.self, forKey: .layout))
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown agent operation type '\(rawType)'")
        }
    }

    @MainActor
    fileprivate func validate(context: inout AgentValidationContext, appendTo errors: inout [String]) async throws {
        switch self {
            case .focusWindow(let target):
                if try await target.resolveWindow() == nil { errors.append("focusWindow: no matching window") }
            case .focusWorkspace(let workspace):
                if Workspace.existing(byName: workspace) == nil { errors.append("focusWorkspace: workspace '\(workspace)' does not exist") }
            case .moveWindowToWorkspace(let windowId, _, _),
                 .setWinMuxFullscreen(let windowId, _, _),
                 .setFloating(let windowId, _),
                 .closeWindow(let windowId, _),
                 .moveWindowOutOfTabGroup(let windowId):
                if Window.get(byId: windowId) == nil { errors.append("Window \(windowId) does not exist") }
            case .moveTabGroupToWorkspace(let tabGroupId, _, _):
                if resolveAgentTabGroup(tabGroupId) == nil, context.plannedTabGroups[tabGroupId] == nil {
                    errors.append("Tab group '\(tabGroupId)' does not exist")
                }
            case .swapPanes(let a, let b):
                if !a.canResolve(in: context) { errors.append("swapPanes: first pane does not exist") }
                if !b.canResolve(in: context) { errors.append("swapPanes: second pane does not exist") }
            case .placePane(let pane, _, let target):
                if !pane.canResolve(in: context) { errors.append("placePane: source pane does not exist") }
                if !target.canResolve(in: context) { errors.append("placePane: target pane does not exist") }
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                if tabs.count < 2 { errors.append("createTabGroup requires at least two tabs") }
                for id in duplicateAgentWindowIds(in: tabs) {
                    errors.append("createTabGroup: window \(id) appears more than once")
                }
                for id in tabs where Window.get(byId: id) == nil { errors.append("createTabGroup: window \(id) does not exist") }
                if let activeWindowId, !tabs.contains(activeWindowId) { errors.append("createTabGroup: activeWindowId must be in tabs") }
                if workspace == nil, Window.get(byId: tabs.first ?? 0)?.nodeWorkspace == nil {
                    errors.append("createTabGroup: workspace is required when the first tab has no workspace")
                }
                if let tabGroupId {
                    context.plannedTabGroups[tabGroupId] = Set(tabs)
                }
            case .addWindowToTabGroup(let windowId, _, let activeWindowId):
                if Window.get(byId: windowId) == nil { errors.append("addWindowToTabGroup: window \(windowId) does not exist") }
                if let activeWindowId, Window.get(byId: activeWindowId) == nil { errors.append("addWindowToTabGroup: active window \(activeWindowId) does not exist") }
                if case .addWindowToTabGroup(_, let tabGroupId, _) = self, resolveAgentTabGroup(tabGroupId) == nil {
                    if context.plannedTabGroups[tabGroupId] == nil {
                        errors.append("addWindowToTabGroup: tab group '\(tabGroupId)' does not exist")
                    }
                }
            case .setActiveTab(let tabGroupId, let windowId):
                let isExistingTab = resolveAgentTabGroup(tabGroupId)?.agentTabWindows.contains(where: { $0.windowId == windowId }) == true
                let isPlannedTab = context.plannedTabGroups[tabGroupId]?.contains(windowId) == true
                if !isExistingTab && !isPlannedTab {
                    errors.append("setActiveTab: window \(windowId) is not in tab group '\(tabGroupId)'")
                }
            case .parkWindow(let pane, _):
                if !pane.canResolve(in: context) { errors.append("parkWindow: pane does not exist") }
            case .setPaneSize(let pane, let axis, _):
                guard let node = pane.resolveNode() else {
                    if pane.canResolve(in: context) { return }
                    errors.append("setPaneSize: pane does not exist")
                    return
                }
                if agentResizableNode(for: node, axis: axis) == nil {
                    if let axis {
                        errors.append("setPaneSize: pane is not inside a \(axis.rawValue) tiled split")
                    } else {
                        errors.append("setPaneSize: pane is not inside a tiled split")
                    }
                }
            case .setWorkspaceLayout(let layout):
                try await layout.validate(appendTo: &errors)
        }
    }

    @MainActor
    fileprivate func apply(context: inout AgentApplyContext) async throws {
        switch self {
            case .focusWindow(let target):
                _ = try await target.resolveWindow()?.focusWindow()
            case .focusWorkspace(let workspace):
                _ = Workspace.existing(byName: workspace)?.focusWorkspace()
            case .moveWindowToWorkspace(let windowId, let workspace, let shouldFocus):
                guard let window = Window.get(byId: windowId) else { return }
                let existedBefore = Workspace.existing(byName: workspace) != nil
                let targetWorkspace = Workspace.get(byName: workspace)
                if !existedBefore {
                    targetWorkspace.assignProject(window.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(window.nodeMonitor ?? focus.workspace.workspaceMonitor)
                _ = agentMoveWindowToWorkspace(window, targetWorkspace, focusFollowsWindow: shouldFocus ?? false)
            case .moveTabGroupToWorkspace(let tabGroupId, let workspace, let shouldFocus):
                guard let group = resolveAgentTabGroup(tabGroupId, context: context) else { return }
                let existedBefore = Workspace.existing(byName: workspace) != nil
                let targetWorkspace = Workspace.get(byName: workspace)
                if !existedBefore {
                    targetWorkspace.assignProject(group.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(group.nodeMonitor ?? focus.workspace.workspaceMonitor)
                let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
                group.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                if shouldFocus ?? false { _ = group.mostRecentWindowRecursive?.focusWindow() }
            case .swapPanes(let a, let b):
                guard let nodeA = a.resolveNode(context: context), let nodeB = b.resolveNode(context: context) else { return }
                swapNodes(nodeA, nodeB)
            case .placePane(let pane, let relation, let target):
                guard let source = pane.resolveNode(context: context), let target = target.resolveNode(context: context) else { return }
                placeAgentPane(source, relation: relation, target: target)
            case .createTabGroup(let tabGroupId, let workspace, let tabs, let activeWindowId):
                let windows = tabs.compactMap { Window.get(byId: $0) }
                guard let first = windows.first else { return }
                let workspaceName = workspace ?? first.nodeWorkspace?.name ?? focus.workspace.name
                let existedBefore = Workspace.existing(byName: workspaceName) != nil
                let targetWorkspace = Workspace.get(byName: workspaceName)
                if !existedBefore {
                    targetWorkspace.assignProject(first.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                for window in windows where window.nodeWorkspace != targetWorkspace {
                    _ = agentMoveWindowToWorkspace(window, targetWorkspace, focusFollowsWindow: false)
                }
                for window in windows.dropFirst() {
                    createOrAppendWindowTabStack(sourceWindow: window, onto: first)
                }
                if let group = first.nearestWindowTabGroup {
                    reorderAgentTabGroup(group, tabs: tabs)
                    if let tabGroupId {
                        context.tabGroupAliases[tabGroupId] = group
                    }
                }
                if let activeWindowId {
                    Window.get(byId: activeWindowId)?.markAsMostRecentChild()
                    _ = Window.get(byId: activeWindowId)?.focusWindow()
                }
            case .addWindowToTabGroup(let windowId, let tabGroupId, let activeWindowId):
                guard let window = Window.get(byId: windowId), let group = resolveAgentTabGroup(tabGroupId, context: context), let target = group.agentTabWindows.first else { return }
                createOrAppendWindowTabStack(sourceWindow: window, onto: target)
                if let activeWindowId {
                    Window.get(byId: activeWindowId)?.markAsMostRecentChild()
                    _ = Window.get(byId: activeWindowId)?.focusWindow()
                }
            case .moveWindowOutOfTabGroup(let windowId):
                guard let window = Window.get(byId: windowId) else { return }
                _ = removeWindowFromTabStack(window)
            case .setActiveTab(let tabGroupId, let windowId):
                guard let window = Window.get(byId: windowId),
                      resolveAgentTabGroup(tabGroupId, context: context)?.agentTabWindows.contains(where: { $0 == window }) == true
                else { return }
                window.markAsMostRecentChild()
                _ = window.focusWindow()
            case .setWinMuxFullscreen(let windowId, let value, let noOuterGaps):
                guard let window = Window.get(byId: windowId) else { return }
                window.isFullscreen = value
                window.noOuterGapsInFullscreen = noOuterGaps ?? window.noOuterGapsInFullscreen
                window.markAsMostRecentChild()
            case .setFloating(let windowId, let value):
                guard let window = Window.get(byId: windowId), let workspace = window.nodeWorkspace else { return }
                if value {
                    window.bindAsFloatingWindow(to: workspace)
                } else if window.isFloating {
                    let binding = workspaceAppendBindingData(targetWorkspace: workspace, index: INDEX_BIND_LAST)
                    window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                }
            case .closeWindow(let windowId, let quitAppIfLastWindow):
                if quitAppIfLastWindow ?? false {
                    var args = CloseCmdArgs(rawArgs: [])
                    args.windowId = windowId
                    args.quitIfLastWindow = true
                    _ = try await CloseCommand(args: args).run(.defaultEnv, .emptyStdin)
                } else {
                    Window.get(byId: windowId)?.closeAxWindow()
                }
            case .parkWindow(let pane, let workspace):
                guard let node = pane.resolveNode(context: context), let sourceWindow = node.mostRecentWindowRecursive ?? node.anyLeafWindowRecursive else { return }
                let workspaceName = workspace ?? "__agent_parked"
                let existedBefore = Workspace.existing(byName: workspaceName) != nil
                let targetWorkspace = Workspace.get(byName: workspaceName)
                if !existedBefore {
                    targetWorkspace.assignProject(node.nodeWorkspace?.projectId ?? focus.workspace.projectId)
                }
                targetWorkspace.seedMonitorIfNeeded(node.nodeMonitor ?? focus.workspace.workspaceMonitor)
                if node is Window, sourceWindow.isFloating {
                    node.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                } else {
                    let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
                    node.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                }
            case .setPaneSize(let pane, let axis, let size):
                guard let node = pane.resolveNode(context: context) else { return }
                setAgentPaneSize(node, axis: axis, size: size)
            case .setWorkspaceLayout(let layout):
                try await layout.apply()
        }
    }
}

struct AgentWindowTarget: Decodable {
    let windowId: UInt32?
    let match: AgentWindowMatch?

    @MainActor
    func resolveWindow() async throws -> Window? {
        if let windowId { return Window.get(byId: windowId) }
        guard let match else { return nil }
        for window in Workspace.all.flatMap(\.allLeafWindowsRecursive) {
            if try await match.matches(window) {
                return window
            }
        }
        return nil
    }
}

struct AgentWindowMatch: Decodable {
    let appName: String?
    let appBundleId: String?
    let titleContains: String?

    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let appName, window.app.name != appName { return false }
        if let appBundleId, window.app.rawAppBundleId != appBundleId { return false }
        if let titleContains, try await !window.title.localizedCaseInsensitiveContains(titleContains) { return false }
        return true
    }
}

struct AgentPaneRef: Codable {
    let paneId: String?
    let windowId: UInt32?
    let tabGroupId: String?

    @MainActor
    fileprivate func resolveNode(context: AgentApplyContext? = nil) -> TreeNode? {
        if let paneId {
            if paneId.hasPrefix("pane-tabgroup-") {
                return resolveAgentTabGroup(String(paneId.dropFirst("pane-".count)), context: context)
            }
            if paneId.hasPrefix("pane-"), let windowId = UInt32(paneId.dropFirst("pane-".count)) {
                return Window.get(byId: windowId)
            }
        }
        if let windowId { return Window.get(byId: windowId) }
        if let tabGroupId { return resolveAgentTabGroup(tabGroupId, context: context) }
        return nil
    }

    @MainActor
    fileprivate func canResolve(in context: AgentValidationContext) -> Bool {
        if resolveNode() != nil { return true }
        if let tabGroupId, context.plannedTabGroups[tabGroupId] != nil { return true }
        if let paneId, paneId.hasPrefix("pane-tabgroup-") {
            return context.plannedTabGroups[String(paneId.dropFirst("pane-".count))] != nil
        }
        return false
    }
}

extension KeyedDecodingContainer where K == AgentOperation.CodingKeys {
    func decodeAgentPaneRef(primaryKey: K, paneIdKey: K, windowIdKey: K) throws -> AgentPaneRef {
        if contains(primaryKey) {
            return try decode(AgentPaneRef.self, forKey: primaryKey)
        }
        if let paneId = try decodeIfPresent(String.self, forKey: paneIdKey) {
            return AgentPaneRef(paneId: paneId, windowId: nil, tabGroupId: nil)
        }
        if let windowId = try decodeIfPresent(UInt32.self, forKey: windowIdKey) {
            return AgentPaneRef(paneId: nil, windowId: windowId, tabGroupId: nil)
        }
        return try decode(AgentPaneRef.self, forKey: primaryKey)
    }

    func decodeWindowIdArray(primaryKey: K, aliasKey: K) throws -> [UInt32] {
        if contains(primaryKey) {
            return try decode([UInt32].self, forKey: primaryKey)
        }
        return try decode([UInt32].self, forKey: aliasKey)
    }

    func decodeAgentSizeAxis(axisKey: K, directionKey: K) throws -> AgentLayoutDirection? {
        if let axis = try decodeIfPresent(AgentLayoutDirection.self, forKey: axisKey) {
            return axis
        }
        return try decodeIfPresent(AgentLayoutDirection.self, forKey: directionKey)
    }
}

extension KeyedDecodingContainer {
    func decodeAgentSizeRatio(sizeKey: K, percentKey: K) throws -> CGFloat {
        if let percent = try decodeIfPresent(CGFloat.self, forKey: percentKey) {
            return try normalizeAgentSizeRatio(percent, percentKey: percentKey)
        }
        return try normalizeAgentSizeRatio(try decode(CGFloat.self, forKey: sizeKey), percentKey: sizeKey)
    }

    func decodeAgentSizeRatioIfPresent(sizeKey: K, percentKey: K) throws -> CGFloat? {
        if let percent = try decodeIfPresent(CGFloat.self, forKey: percentKey) {
            return try normalizeAgentSizeRatio(percent, percentKey: percentKey)
        }
        guard let size = try decodeIfPresent(CGFloat.self, forKey: sizeKey) else { return nil }
        return try normalizeAgentSizeRatio(size, percentKey: sizeKey)
    }
}

private func normalizedAgentOperationType(_ type: String) -> String {
    type.filter { $0 != "_" && $0 != "-" }.lowercased()
}

private func normalizeAgentSizeRatio<K: CodingKey>(_ raw: CGFloat, percentKey key: K) throws -> CGFloat {
    guard raw.isFinite, raw > 0 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [key], debugDescription: "size must be greater than 0"))
    }
    let ratio = raw > 1 ? raw / 100 : raw
    guard ratio > 0, ratio <= 1 else {
        throw DecodingError.dataCorrupted(.init(codingPath: [key], debugDescription: "size must be a ratio from 0 to 1, or a percent from 1 to 100"))
    }
    return ratio
}

enum AgentPaneRelationKind: String, Codable {
    case leftOf
    case rightOf
    case above
    case below

    var orientation: Orientation {
        switch self {
            case .leftOf, .rightOf: .h
            case .above, .below: .v
        }
    }

    var sourceIsAfterTarget: Bool {
        switch self {
            case .rightOf, .below: true
            case .leftOf, .above: false
        }
    }
}

struct AgentWorkspaceLayout: Codable {
    let name: String
    let focusPane: AgentPaneRef?
    let layout: AgentLayoutNode
    let floating: [AgentPaneRef]?

    private enum CodingKeys: String, CodingKey {
        case name
        case focusPane = "focus"
        case layout
        case floating
    }

    @MainActor
    func validate(appendTo errors: inout [String]) async throws {
        var orderedWindowIds: [UInt32] = []
        layout.collectWindowIds(result: &orderedWindowIds)
        for ref in floating ?? [] {
            ref.resolveNode()?.allLeafWindowsRecursive.forEach { orderedWindowIds.append($0.windowId) }
        }

        let windowIds = Set(orderedWindowIds)
        for windowId in duplicateAgentWindowIds(in: orderedWindowIds) {
            errors.append("setWorkspaceLayout '\(name)': window \(windowId) appears more than once")
        }
        for windowId in windowIds where Window.get(byId: windowId) == nil {
            errors.append("setWorkspaceLayout '\(name)': window \(windowId) does not exist")
        }
        for ref in floating ?? [] where ref.resolveNode() == nil {
            errors.append("setWorkspaceLayout '\(name)': floating pane does not exist")
        }
    }

    @MainActor
    func apply() async throws {
        let existedBefore = Workspace.existing(byName: name) != nil
        let workspace = Workspace.get(byName: name)
        if !existedBefore {
            workspace.assignProject(focus.workspace.projectId)
        }
        workspace.seedMonitorIfNeeded(focusPane?.resolveNode()?.nodeMonitor ?? focus.workspace.workspaceMonitor)
        let oldWindows = workspace.allLeafWindowsRecursive
        var referenced: Set<UInt32> = []
        layout.collectWindowIds(result: &referenced)
        for ref in floating ?? [] {
            ref.resolveNode()?.allLeafWindowsRecursive.forEach { referenced.insert($0.windowId) }
        }

        workspace.rootTilingContainer.unbindFromParent()
        switch layout {
            case .split:
                _ = try await layout.bind(into: workspace, index: INDEX_BIND_LAST)
            case .window, .tabGroup:
                _ = try await layout.bind(into: workspace.rootTilingContainer, index: INDEX_BIND_LAST)
        }
        for ref in floating ?? [] {
            if let node = ref.resolveNode(), let window = node as? Window {
                window.bindAsFloatingWindow(to: workspace)
            }
        }

        let root = workspace.rootTilingContainer
        for window in oldWindows where !referenced.contains(window.windowId) && window.isBound {
            if window.nodeWorkspace == nil || window.nodeWorkspace == workspace {
                window.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }
        layout.applySizeRatios(to: root)
        if let focusNode = focusPane?.resolveNode() {
            _ = focusNode.mostRecentWindowRecursive?.focusWindow()
        }
    }
}

indirect enum AgentLayoutNode: Codable {
    case split(direction: AgentLayoutDirection, children: [AgentLayoutNode], size: CGFloat?)
    case window(windowId: UInt32, size: CGFloat?)
    case tabGroup(tabGroupId: String?, tabs: [UInt32], activeWindowId: UInt32?, size: CGFloat?)

    private enum CodingKeys: String, CodingKey {
        case kind
        case direction
        case children
        case windowId
        case tabGroupId
        case tabs
        case activeWindowId
        case size
        case sizePercent
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
            case "split":
                self = .split(
                    direction: try container.decode(AgentLayoutDirection.self, forKey: .direction),
                    children: try container.decode([AgentLayoutNode].self, forKey: .children),
                    size: try container.decodeAgentSizeRatioIfPresent(sizeKey: .size, percentKey: .sizePercent),
                )
            case "window":
                self = .window(
                    windowId: try container.decode(UInt32.self, forKey: .windowId),
                    size: try container.decodeAgentSizeRatioIfPresent(sizeKey: .size, percentKey: .sizePercent),
                )
            case "tabGroup":
                self = .tabGroup(
                    tabGroupId: try container.decodeIfPresent(String.self, forKey: .tabGroupId),
                    tabs: try container.decode([UInt32].self, forKey: .tabs),
                    activeWindowId: try container.decodeIfPresent(UInt32.self, forKey: .activeWindowId),
                    size: try container.decodeAgentSizeRatioIfPresent(sizeKey: .size, percentKey: .sizePercent),
                )
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown layout node kind '\(kind)'")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .split(let direction, let children, let size):
                try container.encode("split", forKey: .kind)
                try container.encode(direction, forKey: .direction)
                try container.encode(children, forKey: .children)
                try container.encodeIfPresent(size, forKey: .size)
            case .window(let windowId, let size):
                try container.encode("window", forKey: .kind)
                try container.encode(windowId, forKey: .windowId)
                try container.encodeIfPresent(size, forKey: .size)
            case .tabGroup(let tabGroupId, let tabs, let activeWindowId, let size):
                try container.encode("tabGroup", forKey: .kind)
                try container.encodeIfPresent(tabGroupId, forKey: .tabGroupId)
                try container.encode(tabs, forKey: .tabs)
                try container.encodeIfPresent(activeWindowId, forKey: .activeWindowId)
                try container.encodeIfPresent(size, forKey: .size)
        }
    }

    func collectWindowIds(result: inout Set<UInt32>) {
        switch self {
            case .split(_, let children, _):
                for child in children { child.collectWindowIds(result: &result) }
            case .window(let windowId, _):
                result.insert(windowId)
            case .tabGroup(_, let tabs, _, _):
                for tab in tabs { result.insert(tab) }
        }
    }

    func collectWindowIds(result: inout [UInt32]) {
        switch self {
            case .split(_, let children, _):
                for child in children { child.collectWindowIds(result: &result) }
            case .window(let windowId, _):
                result.append(windowId)
            case .tabGroup(_, let tabs, _, _):
                result.append(contentsOf: tabs)
        }
    }

    @MainActor
    func bind(into parent: NonLeafTreeNodeObject, index: Int) async throws -> TreeNode? {
        switch self {
            case .split(let direction, let children, _):
                let container = TilingContainer(parent: parent, adaptiveWeight: WEIGHT_AUTO, direction.orientation, .tiles, index: index)
                for child in children {
                    _ = try await child.bind(into: container, index: INDEX_BIND_LAST)
                }
                return container
            case .window(let windowId, _):
                guard let window = Window.get(byId: windowId) else { return nil }
                window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: index)
                return window
            case .tabGroup(_, let tabs, let activeWindowId, _):
                guard !tabs.isEmpty else { return nil }
                let container = TilingContainer(parent: parent, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: index)
                for tab in tabs {
                    Window.get(byId: tab)?.bind(to: container, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                }
                if let activeWindowId {
                    Window.get(byId: activeWindowId)?.markAsMostRecentChild()
                }
                return container
        }
    }

    @MainActor
    func applySizeRatios(to node: TreeNode) {
        guard case .split(_, let childSpecs, _) = self,
              let container = node as? TilingContainer,
              container.layout == .tiles
        else { return }

        applyAgentSizeRatios(to: container, childSpecs: childSpecs)
        for (child, childSpec) in zip(container.children, childSpecs) {
            childSpec.applySizeRatios(to: child)
        }
    }

    var sizeRatio: CGFloat? {
        switch self {
            case .split(_, _, let size), .window(_, let size), .tabGroup(_, _, _, let size):
                size
        }
    }
}

enum AgentLayoutDirection: String, Codable {
    case horizontal
    case vertical

    var orientation: Orientation { self == .horizontal ? .h : .v }
}

// MARK: - Helpers

@MainActor
private func currentAgentWorldId() -> String {
    let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).sortedBy(\.name)
    var lines: [String] = []
    for workspace in workspaces {
        lines.append("workspace|\(workspace.name)|visible:\(workspace.isVisible)|monitor:\(workspace.workspaceMonitor.monitorId_oneBased?.description ?? "nil")")
        lines.append(contentsOf: workspace.rootTilingContainer.agentWorldLines(prefix: "tree|\(workspace.name)"))
        for window in workspace.allLeafWindowsRecursive.sortedBy(\.windowId) {
            lines.append(
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
            )
        }
        for group in workspace.rootTilingContainer.allAgentTabGroupsRecursive.sortedBy({ agentTabGroupId($0) }) {
            lines.append(
                [
                    "tabGroup",
                    agentTabGroupId(group),
                    group.nodeWorkspace?.name ?? "nil",
                    "active:\(group.tabActiveWindow?.windowId.description ?? "nil")",
                    "tabs:\(group.agentTabWindows.map(\.windowId).map(String.init).joined(separator: ","))",
                ].joined(separator: "|")
            )
        }
    }
    return stableAgentHash(lines.joined(separator: "\n"))
}

private func stableAgentHash(_ input: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in input.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}

private func duplicateAgentWindowIds(in ids: [UInt32]) -> [UInt32] {
    var seen: Set<UInt32> = []
    var duplicates: Set<UInt32> = []
    for id in ids where !seen.insert(id).inserted {
        duplicates.insert(id)
    }
    return duplicates.sorted()
}

@MainActor
private func resolveAgentTabGroup(_ id: String, context: AgentApplyContext? = nil) -> TilingContainer? {
    if let alias = context?.tabGroupAliases[id] {
        return alias
    }
    return Workspace.all
        .lazy
        .flatMap { $0.rootTilingContainer.allAgentTabGroupsRecursive }
        .first { agentTabGroupId($0) == id }
}

@MainActor
private func agentTabGroupId(_ group: TilingContainer) -> String {
    let firstWindowId = group.agentTabWindows.first?.windowId ?? group.anyLeafWindowRecursive?.windowId ?? 0
    return "tabgroup-\(firstWindowId)"
}

private func agentPaneIdForTabGroup(tabGroupId: String) -> String {
    "pane-\(tabGroupId)"
}

@MainActor
private func reorderAgentTabGroup(_ group: TilingContainer, tabs: [UInt32]) {
    for tab in tabs {
        Window.get(byId: tab)?.bind(to: group, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
}

@MainActor
private func agentMoveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, focusFollowsWindow: Bool) -> Bool {
    moveWindowToWorkspace(window, targetWorkspace, CmdIo(stdin: .emptyStdin), focusFollowsWindow: focusFollowsWindow, failIfNoop: false)
}

@MainActor
private func setAgentPaneSize(_ node: TreeNode, axis: AgentLayoutDirection?, size: CGFloat) {
    guard let target = agentResizableNode(for: node, axis: axis) else { return }
    applyAgentSizeRatios(
        to: target.parent,
        ratiosByChild: target.parent.children.map { $0 === target.node ? size : nil },
    )
}

@MainActor
private func applyAgentSizeRatios(to container: TilingContainer, childSpecs: [AgentLayoutNode]) {
    applyAgentSizeRatios(
        to: container,
        ratiosByChild: container.children.indices.map { index in
            index < childSpecs.count ? childSpecs[index].sizeRatio : nil
        },
    )
}

@MainActor
private func applyAgentSizeRatios(to container: TilingContainer, ratiosByChild: [CGFloat?]) {
    guard container.layout == .tiles, !container.children.isEmpty else { return }
    let childCount = container.children.count
    let ratiosByChild = Array(ratiosByChild.prefix(childCount)) + Array(repeating: nil, count: max(0, childCount - ratiosByChild.count))
    let explicitTotal = ratiosByChild.compactMap { $0 }.reduce(CGFloat.zero, +)
    let unspecifiedCount = ratiosByChild.count - ratiosByChild.compactMap { $0 }.count
    let ratios: [CGFloat]

    if explicitTotal > 1 || unspecifiedCount == 0 {
        let rawRatios = ratiosByChild.map { $0 ?? 1 }
        let total = rawRatios.reduce(CGFloat.zero, +)
        guard total > 0 else { return }
        ratios = rawRatios.map { $0 / total }
    } else {
        let unspecifiedRatio = unspecifiedCount > 0 ? (1 - explicitTotal) / CGFloat(unspecifiedCount) : 0
        ratios = ratiosByChild.map { $0 ?? unspecifiedRatio }
    }

    let totalWeight = container.getWeight(container.orientation)
    for (child, ratio) in zip(container.children, ratios) {
        child.setWeight(container.orientation, totalWeight * ratio)
    }
}

@MainActor
private func agentResizableNode(for node: TreeNode, axis: AgentLayoutDirection? = nil) -> (node: TreeNode, parent: TilingContainer)? {
    let paneNode = node.agentPaneSizingNode
    for candidate in paneNode.parentsWithSelf {
        guard let parent = candidate.parent as? TilingContainer,
              parent.layout == .tiles,
              axis == nil || parent.orientation == axis?.orientation
        else { continue }
        return (candidate, parent)
    }
    return nil
}

@MainActor
private func placeAgentPane(_ source: TreeNode, relation: AgentPaneRelationKind, target: TreeNode) {
    if source == target || source.parentsWithSelf.contains(target) || target.parentsWithSelf.contains(source) {
        return
    }
    if let insertion = target.agentNearestInsertionParent(orientation: relation.orientation) {
        var insertIndex = insertion.anchor.ownIndex.orDie() + (relation.sourceIsAfterTarget ? 1 : 0)
        if source.parent === insertion.parent, let sourceIndex = source.ownIndex, sourceIndex < insertIndex {
            insertIndex -= 1
        }
        source.bind(to: insertion.parent, adaptiveWeight: WEIGHT_AUTO, index: insertIndex)
        source.mostRecentWindowRecursive?.markAsMostRecentChild()
        return
    }

    _ = source.unbindFromParent()
    guard target.parent != nil else { return }
    let targetBinding = target.unbindFromParent()
    let newParent = TilingContainer(parent: targetBinding.parent, adaptiveWeight: targetBinding.adaptiveWeight, relation.orientation, .tiles, index: targetBinding.index)
    if relation.sourceIsAfterTarget {
        target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        source.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    } else {
        source.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }
    source.mostRecentWindowRecursive?.markAsMostRecentChild()
}

extension TreeNode {
    @MainActor
    fileprivate var agentPaneId: String? {
        if let group = (self as? Window)?.nearestWindowTabGroup {
            return agentPaneIdForTabGroup(tabGroupId: agentTabGroupId(group))
        }
        if let window = self as? Window {
            return "pane-\(window.windowId)"
        }
        if let group = self as? TilingContainer, group.isWindowTabGroup {
            return agentPaneIdForTabGroup(tabGroupId: agentTabGroupId(group))
        }
        return nil
    }

    fileprivate func agentNearestInsertionParent(orientation: Orientation) -> (parent: TilingContainer, anchor: TreeNode)? {
        for node in parentsWithSelf {
            guard let parent = node.parent as? TilingContainer,
                  parent.layout == .tiles,
                  parent.orientation == orientation,
                  let anchor = node.directChild(in: parent)
            else { continue }
            return (parent, anchor)
        }
        return nil
    }

    @MainActor
    fileprivate var agentPaneSizingNode: TreeNode {
        (self as? Window)?.nearestWindowTabGroup ?? self
    }

    @MainActor
    fileprivate var agentSizeRatio: CGFloat? {
        guard let parent = parent as? TilingContainer,
              parent.layout == .tiles
        else { return nil }
        let total = parent.children.reduce(CGFloat.zero) { $0 + $1.getWeight(parent.orientation) }
        guard total > 0 else { return nil }
        return getWeight(parent.orientation) / total
    }

    @MainActor
    fileprivate var agentSizeAxis: AgentLayoutDirection? {
        guard let parent = parent as? TilingContainer,
              parent.layout == .tiles
        else { return nil }
        return parent.orientation == .h ? .horizontal : .vertical
    }
}

extension Window {
    @MainActor
    fileprivate var agentLayoutDescription: String {
        guard let parent else { return "unbound" }
        return switch getChildParentRelation(child: self, parent: parent) {
            case .floatingWindow: "floating"
            case .tiling(let parent): "\(parent.orientation.rawValue)_\(parent.layout.rawValue)"
            case .macosNativeFullscreenWindow: "macos_native_fullscreen"
            case .macosNativeHiddenAppWindow: "macos_native_hidden_app"
            case .macosNativeMinimizedWindow: "macos_native_minimized"
            case .macosPopupWindow: "macos_popup"
            case .rootTilingContainer, .shimContainerRelation: "internal"
        }
    }
}

extension TilingContainer {
    @MainActor
    fileprivate var allAgentTabGroupsRecursive: [TilingContainer] {
        var result: [TilingContainer] = []
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer else { return }
            if container.isWindowTabGroup {
                result.append(container)
                return
            }
            for child in container.children {
                visit(child)
            }
        }
        visit(self)
        return result
    }

    @MainActor
    fileprivate var agentTabWindows: [Window] {
        children.compactMap { $0.tabRepresentativeWindow ?? $0.mostRecentWindowRecursive ?? $0.anyLeafWindowRecursive }
    }

    @MainActor
    fileprivate func agentRawLayoutNode() -> AgentRawLayoutNode {
        if isWindowTabGroup {
            return .tabGroup(
                tabGroupId: agentTabGroupId(self),
                activeWindowId: tabActiveWindow?.windowId,
                tabs: agentTabWindows.map(\.windowId),
                size: agentSizeRatio,
            )
        }
        return .split(
            direction: orientation == .h ? .horizontal : .vertical,
            layout: layout.rawValue,
            size: agentSizeRatio,
            children: children.compactMap { child in
                if let window = child as? Window {
                    return .window(windowId: window.windowId, size: window.agentSizeRatio)
                }
                if let container = child as? TilingContainer {
                    return container.agentRawLayoutNode()
                }
                return nil
            },
        )
    }

    @MainActor
    fileprivate func agentWorldLines(prefix: String) -> [String] {
        let nodeId: String
        if isWindowTabGroup {
            nodeId = "tabGroup:\(agentTabGroupId(self))"
        } else {
            nodeId = "container:\(orientation.rawValue):\(layout.rawValue)"
        }
        let weight = (parent as? TilingContainer).map { "|weight:\(getWeight($0.orientation))" } ?? ""
        var result = ["\(prefix)|\(nodeId)\(weight)|children:\(children.count)"]
        for (index, child) in children.enumerated() {
            let childPrefix = "\(prefix).\(index)"
            if let window = child as? Window {
                result.append("\(childPrefix)|window:\(window.windowId)|weight:\(window.getWeight(orientation))")
            } else if let container = child as? TilingContainer {
                result.append(contentsOf: container.agentWorldLines(prefix: childPrefix))
            }
        }
        return result
    }
}

extension Workspace {
    @MainActor
    fileprivate func agentPaneInfos() -> [AgentPaneInfo] {
        var result: [AgentPaneInfo] = floatingWindows.map {
            AgentPaneInfo(
                paneId: "pane-\($0.windowId)",
                kind: .window,
                workspace: name,
                windowId: $0.windowId,
                tabGroupId: nil,
                label: $0.app.name ?? $0.app.rawAppBundleId ?? "Window \($0.windowId)",
                size: $0.agentPaneSizingNode.agentSizeRatio,
                sizeAxis: $0.agentPaneSizingNode.agentSizeAxis,
                frame: ($0.lastKnownActualRect ?? $0.lastAppliedLayoutPhysicalRect ?? $0.lastAppliedLayoutVirtualRect).map(AgentRect.init),
            )
        }

        func visit(_ node: TreeNode) {
            switch node.nodeCases {
                case .window(let window):
                    result.append(AgentPaneInfo(
                        paneId: "pane-\(window.windowId)",
                        kind: .window,
                        workspace: name,
                        windowId: window.windowId,
                        tabGroupId: nil,
                        label: window.app.name ?? window.app.rawAppBundleId ?? "Window \(window.windowId)",
                        size: window.agentPaneSizingNode.agentSizeRatio,
                        sizeAxis: window.agentPaneSizingNode.agentSizeAxis,
                        frame: (window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutVirtualRect).map(AgentRect.init),
                    ))
                case .tilingContainer(let container):
                    if container.isWindowTabGroup {
                        let tabGroupId = agentTabGroupId(container)
                        result.append(AgentPaneInfo(
                            paneId: agentPaneIdForTabGroup(tabGroupId: tabGroupId),
                            kind: .tabGroup,
                            workspace: name,
                            windowId: nil,
                            tabGroupId: tabGroupId,
                            label: "Tab Group \(container.agentTabWindows.map(\.windowId))",
                            size: container.agentSizeRatio,
                            sizeAxis: container.agentSizeAxis,
                            frame: (container.lastAppliedLayoutPhysicalRect ?? container.lastAppliedLayoutVirtualRect).map(AgentRect.init),
                        ))
                    } else {
                        for child in container.children { visit(child) }
                    }
                case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                     .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer:
                    break
            }
        }
        visit(rootTilingContainer)
        return result
    }

    @MainActor
    fileprivate func agentPaneRelations() -> [AgentPaneRelation] {
        var byPane: [String: AgentPaneRelation] = [:]
        func relation(_ paneId: String) -> AgentPaneRelation {
            byPane[paneId] ?? AgentPaneRelation(workspace: name, paneId: paneId)
        }
        func set(_ paneId: String, _ keyPath: WritableKeyPath<AgentPaneRelation, String?>, _ value: String?) {
            guard let value else { return }
            var item = relation(paneId)
            item[keyPath: keyPath] = value
            byPane[paneId] = item
        }
        func paneIds(_ node: TreeNode) -> [String] {
            if let paneId = node.agentPaneId { return [paneId] }
            return node.children.flatMap(paneIds)
        }
        func visit(_ node: TreeNode) {
            guard let container = node as? TilingContainer, !container.isWindowTabGroup else { return }
            let childPaneIds = container.children.map(paneIds)
            for index in childPaneIds.indices.dropLast() {
                for lhs in childPaneIds[index] {
                    for rhs in childPaneIds[index + 1] {
                        if container.orientation == .h {
                            set(lhs, \.right, rhs)
                            set(rhs, \.left, lhs)
                        } else {
                            set(lhs, \.below, rhs)
                            set(rhs, \.above, lhs)
                        }
                    }
                }
            }
            for child in container.children { visit(child) }
        }
        visit(rootTilingContainer)
        return Array(byPane.values)
    }
}
