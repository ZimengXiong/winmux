import AppKit
import Common
import Foundation

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
}
