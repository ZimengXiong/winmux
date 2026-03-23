@testable import AppBundle
import XCTest

final class WindowTabsTest: XCTestCase {
    @MainActor
    func testCreateTabStackFromTwoSiblingWindows() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)

        createOrAppendWindowTabStack(sourceWindow: source, onto: target)

        assertEquals(root.layoutDescription, .h_tiles([.v_accordion([.window(2), .window(1)])]))
    }

    @MainActor
    func testAppendWindowToExistingTabStack() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        let target = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)
        let source = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        createOrAppendWindowTabStack(sourceWindow: source, onto: target)

        assertEquals(root.layoutDescription, .h_accordion([.window(2), .window(1), .window(3)]))
    }

    @MainActor
    func testRemoveWindowFromNestedTabStack() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leading = TestWindow.new(id: 0, parent: root)
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 1, parent: stack)
        let stackedB = TestWindow.new(id: 2, parent: stack)

        XCTAssertTrue(removeWindowFromTabStack(stackedB))

        assertEquals(leading.focusWindow(), true)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_accordion([
                .window(1),
            ]),
            .window(2),
        ]))
    }

    @MainActor
    func testWindowDropAndSwapZonesDoNotOverlap() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 220)

        let tabDropZone = window.tabDropZoneRect.orDie()
        let tabInteractionZone = window.tabDropInteractionRect.orDie()
        let swapDropZone = window.swapDropZoneRect.orDie()

        XCTAssertGreaterThan(tabInteractionZone.height, tabDropZone.height)
        XCTAssertGreaterThan(swapDropZone.minY, tabDropZone.maxY)
    }

    @MainActor
    func testAccordionDropAndSwapZonesDoNotOverlap() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 260)

        let tabBarRect = accordion.windowTabBarRect.orDie()
        let tabDropZone = accordion.windowTabDropZoneRect.orDie()
        let tabInteractionZone = accordion.windowTabDropInteractionRect.orDie()
        let swapDropZone = accordion.swapDropZoneRect.orDie()

        XCTAssertGreaterThan(tabDropZone.height, tabBarRect.height)
        XCTAssertGreaterThan(tabInteractionZone.height, tabDropZone.height)
        XCTAssertGreaterThan(swapDropZone.minY, tabDropZone.maxY)
    }

    @MainActor
    func testWindowSwapZoneKeepsCenterActive() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 360, height: 240)

        let swapDropZone = window.swapDropZoneRect.orDie()
        XCTAssertTrue(swapDropZone.contains(swapDropZone.center))
    }

    @MainActor
    func testAccordionSwapZoneKeepsBodyActive() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)

        let swapDropZone = accordion.swapDropZoneRect.orDie()
        XCTAssertTrue(swapDropZone.contains(swapDropZone.center))
    }

    @MainActor
    func testTabDetachKeepRectsDifferentiateWindowAndTabStripDrags() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        let windowKeepRect = window.tabDetachKeepRect(origin: .window).orDie()
        let stripKeepRect = window.tabDetachKeepRect(origin: .tabStrip).orDie()

        XCTAssertGreaterThan(windowKeepRect.height, stripKeepRect.height)
        XCTAssertLessThan(stripKeepRect.maxY, windowKeepRect.maxY)
        XCTAssertLessThan(windowKeepRect.width, accordion.lastAppliedLayoutPhysicalRect.orDie().width)
    }

    @MainActor
    func testWindowAndAccordionTabInsertZonesUseSameTopBarShape() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)

        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let accordionWindow = TestWindow.new(id: 2, parent: accordion)
        _ = TestWindow.new(id: 3, parent: accordion)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        accordionWindow.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        let windowZone = window.tabDropZoneRect.orDie()
        let accordionZone = accordionWindow.tabDropZoneRect.orDie()
        let accordionRect = accordionWindow.lastAppliedLayoutPhysicalRect.orDie()

        XCTAssertEqual(windowZone.height, accordionZone.height)
        XCTAssertEqual(windowZone.minX, accordionZone.minX)
        XCTAssertEqual(windowZone.maxX, accordionZone.maxX)
        XCTAssertGreaterThanOrEqual(accordionZone.topLeftY, accordionRect.topLeftY)
        XCTAssertLessThanOrEqual(accordionZone.topLeftY, accordionRect.topLeftY + 6)
    }

    @MainActor
    func testFullscreenActiveTabHidesTabStripWithoutDisablingAccordionBehavior() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let accordion = workspace.rootTilingContainer
        accordion.layout = .accordion
        let active = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        active.isFullscreen = true
        active.markAsMostRecentChild()

        XCTAssertTrue(accordion.usesWindowTabBehavior)
        XCTAssertFalse(accordion.showsWindowTabs)
        XCTAssertEqual(accordion.windowTabBarHeight, 0)
        XCTAssertNil(accordion.windowTabBarRect)
    }

    @MainActor
    func testFullscreenWindowInAccordionCoversSiblingWindows() async throws {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let fullscreenWindow = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
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
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let fullscreenWindow = TestWindow.new(id: 1, parent: root)
        _ = TestWindow.new(id: 2, parent: accordion)
        _ = TestWindow.new(id: 3, parent: accordion)
        accordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        fullscreenWindow.isFullscreen = true
        TrayMenuModel.shared.isEnabled = true

        await updateWindowTabModel()

        XCTAssertTrue(TrayMenuModel.shared.windowTabStrips.isEmpty)
    }
}
