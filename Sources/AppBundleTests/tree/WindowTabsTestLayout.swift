@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    func testMovedObsIgnoresSidebarManagedDragSession() {
        XCTAssertTrue(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 10,
            currentWindowId: 10,
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: true,
        ))
    }

    func testMovedObsIgnoresTabStripDetachDragSession() {
        XCTAssertTrue(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 10,
            currentWindowId: 10,
            kind: .move,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
        ))
    }

    func testMovedObsIgnoresManagedGroupBodyDragSession() {
        XCTAssertTrue(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 10,
            currentWindowId: 10,
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
    }

    func testMovedObsKeepsNormalBodyDragSessionActive() {
        XCTAssertFalse(shouldIgnoreMovedObsForManagedWindowDragSession(
            observedWindowId: 10,
            currentWindowId: 10,
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
    }

    @MainActor
    func testSwapDestinationIsSuppressedForFloatingWindowSource() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let source = TestWindow.new(id: 1, parent: workspace)

        XCTAssertTrue(shouldSuppressSwapDestination(sourceWindow: source, subject: .window))
    }

    @MainActor
    func testSwapDestinationGateAllowsTiledWindowSource() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let source = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        XCTAssertFalse(shouldSuppressSwapDestination(sourceWindow: source, subject: .window))
    }

    @MainActor
    func testCrossWorkspaceBodyMovePreservesFloatingSourceLayout() {
        setUpWorkspacesForTests()
        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace)
        let targetWorkspace = Workspace.get(byName: "target")
        let target = TestWindow.new(id: 10, parent: targetWorkspace.rootTilingContainer)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 360, height: 240)

        applyWorkspaceMove(
            sourceNode: source,
            sourceWindow: source,
            mouseLocation: CGPoint(x: 50, y: 50),
            targetWorkspace: targetWorkspace,
        )

        XCTAssertTrue(source.parent === targetWorkspace)
        XCTAssertTrue(targetWorkspace.floatingWindows.contains(source))
        XCTAssertEqual(targetWorkspace.rootTilingContainer.children.count, 1)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === target)
    }

    @MainActor
    func testWindowAndTabGroupTabInsertZonesUseSameTopBarShape() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)

        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let tabGroupWindow = TestWindow.new(id: 2, parent: tabGroup)
        _ = TestWindow.new(id: 3, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        tabGroupWindow.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        let windowZone = window.tabDropZoneRect.orDie()
        let tabGroupZone = tabGroupWindow.tabDropZoneRect.orDie()
        let tabGroupRect = tabGroupWindow.lastAppliedLayoutPhysicalRect.orDie()

        XCTAssertEqual(windowZone.height, tabGroupZone.height)
        XCTAssertEqual(windowZone.minX, tabGroupZone.minX)
        XCTAssertEqual(windowZone.maxX, tabGroupZone.maxX)
        XCTAssertGreaterThanOrEqual(tabGroupZone.topLeftY, tabGroupRect.topLeftY)
        XCTAssertLessThanOrEqual(tabGroupZone.topLeftY, tabGroupRect.topLeftY + 6)
    }

    @MainActor
    func testTabInsertAndTopSplitIntentZonesTouchWithoutDeadBand() {
        setUpWorkspacesForTests()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)

        let windowTabInteraction = window.tabDropInteractionRect.orDie()
        let windowTopSplitInteraction = window.stackSplitDropZoneRect(position: .above).orDie()

        XCTAssertEqual(windowTopSplitInteraction.minY, windowTabInteraction.maxY, accuracy: 0.001)
    }

    @MainActor
    func testTabGroupTabInsertAndTopSplitIntentZonesTouchWithoutDeadBand() {
        setUpWorkspacesForTests()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let active = TestWindow.new(id: 1, parent: tabGroup)
        let second = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        active.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)
        second.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        let tabInteraction = tabGroup.windowTabDropInteractionRect.orDie()
        let topSplitInteraction = tabGroup.stackSplitDropZoneRect(position: .above).orDie()

        XCTAssertEqual(topSplitInteraction.minY, tabInteraction.maxY, accuracy: 0.001)
    }

    @MainActor
    func testFullscreenActiveTabHidesTabStripWithoutDisablingTabGroupBehavior() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = workspace.rootTilingContainer
        tabGroup.layout = .tabGroup
        let active = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        active.isFullscreen = true
        active.markAsMostRecentChild()

        XCTAssertTrue(tabGroup.usesWindowTabBehavior)
        XCTAssertFalse(tabGroup.showsWindowTabs)
        XCTAssertEqual(tabGroup.windowTabBarHeight, 0)
        XCTAssertNil(tabGroup.windowTabBarRect)
    }

    @MainActor
    func testFullscreenWindowInTabGroupCoversSiblingWindows() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let fullscreenWindow = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        let siblingWindow = TestWindow.new(id: 3, parent: root)

        fullscreenWindow.isFullscreen = true
        fullscreenWindow.markAsMostRecentChild()

        try await workspace.layoutWorkspace()

        XCTAssertNil(siblingWindow.lastAppliedLayoutPhysicalRect)
        XCTAssertNil(siblingWindow.lastAppliedLayoutVirtualRect)
        XCTAssertNil(fullscreenWindow.lastAppliedLayoutPhysicalRect)
        let fullscreenRect = try await fullscreenWindow.getAxRect().orDie()
        let expectedRect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        XCTAssertEqual(fullscreenRect.topLeftX, expectedRect.topLeftX)
        XCTAssertEqual(fullscreenRect.topLeftY, expectedRect.topLeftY)
        XCTAssertEqual(fullscreenRect.width, expectedRect.width)
        XCTAssertEqual(fullscreenRect.height, expectedRect.height)
    }

    @MainActor
    func testWorkspaceWithFullscreenWindowShowsNoTabStrips() async {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let fullscreenWindow = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        _ = TestWindow.new(id: 3, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        fullscreenWindow.isFullscreen = true
        TrayMenuModel.shared.isEnabled = true

        await updateWindowTabModel()

        XCTAssertTrue(TrayMenuModel.shared.windowTabStrips.isEmpty)
    }
}
