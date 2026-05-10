@testable import DeckCore
import XCTest

final class DeckRoutingPlannerTests: XCTestCase {
    func testPlansTabGroupCreationForWindowsWithSameRoute() {
        let profile = DeckProfile(
            name: "winmux",
            actions: [
                DeckAction(
                    name: "Editor",
                    type: .app,
                    app: "Visual Studio Code",
                    route: DeckRoute(workspace: "code", tabGroup: "tools"),
                    match: DeckWindowMatch(bundleId: "com.microsoft.VSCode"),
                ),
                DeckAction(
                    name: "Terminal",
                    type: .terminal,
                    command: "codex",
                    route: DeckRoute(workspace: "code", tabGroup: "tools"),
                    match: DeckWindowMatch(bundleId: "com.apple.Terminal"),
                ),
            ],
        )
        let before = DeckAgentSnapshot(
            worldId: "1",
            inventory: DeckAgentInventory(windows: [], tabGroups: [], workspaces: []),
        )
        let after = DeckAgentSnapshot(
            worldId: "2",
            inventory: DeckAgentInventory(
                windows: [
                    DeckAgentWindow(windowId: 1, title: "winmux", appName: "Code", appBundleId: "com.microsoft.VSCode", workspace: nil, tabGroupId: nil),
                    DeckAgentWindow(windowId: 2, title: "codex", appName: "Terminal", appBundleId: "com.apple.Terminal", workspace: nil, tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )

        let (operations, summary) = DeckRoutingPlanner.plan(profile: profile, before: before, after: after)

        XCTAssertEqual(summary.routedWindowIds, [1, 2])
        XCTAssertEqual(operations, [
            .createTabGroup(tabGroupId: nil, workspace: "code", tabs: [1, 2], activeWindowId: nil),
        ])
    }

    func testIgnoresExistingWindowsUnlessRouteReusesExisting() {
        let profile = DeckProfile(
            name: "browser",
            actions: [
                DeckAction(
                    name: "Chrome",
                    type: .browser,
                    urls: ["https://example.com"],
                    route: DeckRoute(workspace: "browser", reuseExisting: false),
                    match: DeckWindowMatch(bundleId: "com.google.Chrome"),
                ),
            ],
        )
        let before = DeckAgentSnapshot(
            worldId: "1",
            inventory: DeckAgentInventory(
                windows: [
                    DeckAgentWindow(windowId: 10, title: "Existing", appName: "Chrome", appBundleId: "com.google.Chrome", workspace: "1", tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )
        let after = before

        let (operations, summary) = DeckRoutingPlanner.plan(profile: profile, before: before, after: after)

        XCTAssertTrue(summary.routedWindowIds.isEmpty)
        XCTAssertTrue(operations.isEmpty)
    }

    func testCandidateReadinessRequiresEveryRoutedAction() {
        let profile = DeckProfile(
            name: "winmux",
            actions: [
                DeckAction(
                    type: .app,
                    app: "Visual Studio Code",
                    route: DeckRoute(workspace: "code"),
                    match: DeckWindowMatch(bundleId: "com.microsoft.VSCode"),
                ),
                DeckAction(
                    type: .terminal,
                    command: "codex",
                    route: DeckRoute(workspace: "code"),
                    match: DeckWindowMatch(bundleId: "com.apple.Terminal"),
                ),
            ],
        )
        let before = DeckAgentSnapshot(worldId: "1", inventory: DeckAgentInventory(windows: [], tabGroups: [], workspaces: []))
        let partialAfter = DeckAgentSnapshot(
            worldId: "2",
            inventory: DeckAgentInventory(
                windows: [
                    DeckAgentWindow(windowId: 1, title: "winmux", appName: "Code", appBundleId: "com.microsoft.VSCode", workspace: nil, tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )

        XCTAssertFalse(DeckRoutingPlanner.hasCandidateForEveryRoutedAction(profile: profile, before: before, after: partialAfter))
    }

    func testCandidateReadinessCountsActionsWithSameMatcherSeparately() {
        let profile = DeckProfile(
            name: "agents",
            actions: [
                DeckAction(
                    type: .shell,
                    run: "codex",
                    route: DeckRoute(workspace: "agents", tabGroup: "terminals"),
                    match: DeckWindowMatch(bundleId: "com.cmuxterm.app"),
                ),
                DeckAction(
                    type: .shell,
                    run: "git status",
                    route: DeckRoute(workspace: "agents", tabGroup: "terminals"),
                    match: DeckWindowMatch(bundleId: "com.cmuxterm.app"),
                ),
            ],
        )
        let before = DeckAgentSnapshot(worldId: "1", inventory: DeckAgentInventory(windows: [], tabGroups: [], workspaces: []))
        let oneWindow = DeckAgentSnapshot(
            worldId: "2",
            inventory: DeckAgentInventory(
                windows: [
                    DeckAgentWindow(windowId: 1, title: "cmux", appName: "cmux", appBundleId: "com.cmuxterm.app", workspace: nil, tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )
        let twoWindows = DeckAgentSnapshot(
            worldId: "3",
            inventory: DeckAgentInventory(
                windows: oneWindow.inventory.windows + [
                    DeckAgentWindow(windowId: 2, title: "cmux", appName: "cmux", appBundleId: "com.cmuxterm.app", workspace: nil, tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )

        XCTAssertFalse(DeckRoutingPlanner.hasCandidateForEveryRoutedAction(profile: profile, before: before, after: oneWindow))
        XCTAssertTrue(DeckRoutingPlanner.hasCandidateForEveryRoutedAction(profile: profile, before: before, after: twoWindows))
    }

    func testRoutableCandidateWindowIdsIncludesPartialMatches() {
        let profile = DeckProfile(
            name: "winmux",
            actions: [
                DeckAction(
                    type: .app,
                    app: "Visual Studio Code",
                    route: DeckRoute(workspace: "code"),
                    match: DeckWindowMatch(bundleId: "com.microsoft.VSCode"),
                ),
                DeckAction(
                    type: .terminal,
                    command: "codex",
                    route: DeckRoute(workspace: "agents"),
                    match: DeckWindowMatch(bundleId: "com.cmuxterm.app"),
                ),
            ],
        )
        let before = DeckAgentSnapshot(
            worldId: "1",
            inventory: DeckAgentInventory(
                windows: [
                    DeckAgentWindow(windowId: 10, title: "Existing", appName: "Code", appBundleId: "com.microsoft.VSCode", workspace: "old", tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )
        let after = DeckAgentSnapshot(
            worldId: "2",
            inventory: DeckAgentInventory(
                windows: before.inventory.windows + [
                    DeckAgentWindow(windowId: 11, title: "winmux", appName: "Code", appBundleId: "com.microsoft.VSCode", workspace: nil, tabGroupId: nil),
                ],
                tabGroups: [],
                workspaces: [],
            ),
        )

        XCTAssertEqual(
            DeckRoutingPlanner.routableCandidateWindowIds(profile: profile, before: before, after: after),
            [11],
        )
    }
}
