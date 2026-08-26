@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    func testSameTabGroupTabStripReentryPrioritizesTabTakeBackIntent() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        config.windowTabs.enabled = true

        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        let mouseLocation = tabGroup.windowTabDropInteractionRect.orDie().center
        let destination = selfTabGroupTabReentryDestination(
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .tabStrip,
        ).orDie()

        XCTAssertEqual(destination.dropIntentOverlay?.targetFrame, tabGroup.windowDragVisibleRect)
        XCTAssertEqual(destination.dropIntentOverlay?.activeZone, .tab)

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .tabStrip,
        ))

        let pendingIntent = debugPendingWindowDragIntentSummary().orDie()
        let expectedPreviewRect = tabGroup.windowTabDropZoneRect.orDie()
        let expectedInteractionRect = tabGroup.windowTabDropInteractionRect.orDie()
        XCTAssertEqual(pendingIntent.kind, .reorderTab(windowId: source.windowId, targetIndex: 0))
        XCTAssertEqual(pendingIntent.previewRect.topLeftX, expectedPreviewRect.topLeftX)
        XCTAssertEqual(pendingIntent.previewRect.topLeftY, expectedPreviewRect.topLeftY)
        XCTAssertEqual(pendingIntent.previewRect.width, expectedPreviewRect.width)
        XCTAssertEqual(pendingIntent.previewRect.height, expectedPreviewRect.height)
        XCTAssertEqual(pendingIntent.interactionRect.topLeftX, expectedInteractionRect.topLeftX)
        XCTAssertEqual(pendingIntent.interactionRect.topLeftY, expectedInteractionRect.topLeftY)
        XCTAssertEqual(pendingIntent.interactionRect.width, expectedInteractionRect.width)
        XCTAssertEqual(pendingIntent.interactionRect.height, expectedInteractionRect.height)
    }

    func testSameTabGroupMiddleIntentKeepsTheOverlayVisible() {
        setUpWorkspacesForTests()
        let previousWindowTabs = config.windowTabs.enabled
        config.windowTabs.enabled = true
        defer { config.windowTabs.enabled = previousWindowTabs }

        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        tabGroup.lastAppliedLayoutPhysicalRect = groupRect
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)
        target.lastAppliedLayoutPhysicalRect = source.lastAppliedLayoutPhysicalRect
        let mouseLocation = CGPoint(x: groupRect.center.x, y: groupRect.center.y)
        let resolution = resolveWindowDropIntent(
            sourceWindow: source,
            targetWindow: target,
            targetNode: tabGroup,
            mouseLocation: mouseLocation,
        ).orDie()

        XCTAssertEqual(resolution.intent.zone, .middle)
        let destination = destinationFromWindowDropIntent(
            resolution,
            sourceWindow: source,
            targetWindow: target,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .tabStrip,
        ).orDie()

        XCTAssertEqual(destination.kind, .reorderTab(windowId: source.windowId, targetIndex: 0))
        XCTAssertEqual(destination.dropIntentOverlay?.activeZone, .middle)
    }

    func testTabStackOntoHiddenTabbedWindowUsesGroupContentRect() {
        setUpWorkspacesForTests()
        config.windowTabs.enabled = true

        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let active = TestWindow.new(id: 2, parent: tabGroup)
        let hiddenTarget = TestWindow.new(
            id: 3,
            parent: tabGroup,
            rect: Rect(topLeftX: 2559, topLeftY: 1408, width: 1338, height: 1376),
        )
        let groupRect = Rect(topLeftX: 1203.75, topLeftY: 12, width: 1344.25, height: 1415)
        tabGroup.lastAppliedLayoutPhysicalRect = groupRect
        active.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 1206, topLeftY: 48, width: 1338, height: 1376)
        hiddenTarget.lastAppliedLayoutPhysicalRect = nil
        active.markAsMostRecentChild()
        let hiddenTargetOldX = hiddenTarget.lastKnownActualRect?.topLeftX
        let expectedRect = resolvedTabStackNormalizedRect(targetWindow: hiddenTarget).orDie()

        createOrAppendWindowTabStack(sourceWindow: source, onto: hiddenTarget)

        XCTAssertTrue(source.parent === tabGroup)
        XCTAssertEqual(source.lastKnownActualRect?.topLeftX, expectedRect.topLeftX)
        XCTAssertEqual(source.lastKnownActualRect?.topLeftY, expectedRect.topLeftY)
        XCTAssertEqual(source.lastKnownActualRect?.width, expectedRect.width)
        XCTAssertEqual(source.lastKnownActualRect?.height, expectedRect.height)
        XCTAssertNotEqual(source.lastKnownActualRect?.topLeftX, hiddenTargetOldX)
    }

    @MainActor
    func testResolvedDraggedWindowAnchorRectUsesWholeGroupForGroupDrag() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        let windowRect = Rect(topLeftX: 12, topLeftY: 40, width: 300, height: 220)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 260)
        window.lastAppliedLayoutPhysicalRect = windowRect
        tabGroup.lastAppliedLayoutPhysicalRect = groupRect

        let resolvedWindowRect = resolvedDraggedWindowAnchorRect(for: window, subject: .window).orDie()
        XCTAssertEqual(resolvedWindowRect.topLeftX, windowRect.topLeftX)
        XCTAssertEqual(resolvedWindowRect.topLeftY, windowRect.topLeftY)
        XCTAssertEqual(resolvedWindowRect.width, windowRect.width)
        XCTAssertEqual(resolvedWindowRect.height, windowRect.height)

        let resolvedGroupRect = resolvedDraggedWindowAnchorRect(for: window, subject: .group).orDie()
        XCTAssertEqual(resolvedGroupRect.topLeftX, groupRect.topLeftX)
        XCTAssertEqual(resolvedGroupRect.topLeftY, groupRect.topLeftY)
        XCTAssertEqual(resolvedGroupRect.width, groupRect.width)
        XCTAssertEqual(resolvedGroupRect.height, groupRect.height)
    }

    @MainActor
    func testPinnedDraggedWindowRectUsesWindowRectForGroupSidebarDrag() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        let windowRect = Rect(topLeftX: 12, topLeftY: 40, width: 300, height: 220)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 260)
        window.lastAppliedLayoutPhysicalRect = windowRect
        tabGroup.lastAppliedLayoutPhysicalRect = groupRect

        let pinnedRect = pinnedDraggedWindowRect(
            for: window,
            subject: .group,
            fallbackAnchorRect: groupRect,
        )

        XCTAssertEqual(pinnedRect.topLeftX, windowRect.topLeftX)
        XCTAssertEqual(pinnedRect.topLeftY, windowRect.topLeftY)
        XCTAssertEqual(pinnedRect.width, windowRect.width)
        XCTAssertEqual(pinnedRect.height, windowRect.height)
    }

    @MainActor
    func testPinnedDraggedWindowRectFallsBackWhenWindowRectMissing() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 260)
        tabGroup.lastAppliedLayoutPhysicalRect = groupRect

        let pinnedRect = pinnedDraggedWindowRect(
            for: window,
            subject: .group,
            fallbackAnchorRect: groupRect,
        )

        XCTAssertEqual(pinnedRect.topLeftX, groupRect.topLeftX)
        XCTAssertEqual(pinnedRect.topLeftY, groupRect.topLeftY)
        XCTAssertEqual(pinnedRect.width, groupRect.width)
        XCTAssertEqual(pinnedRect.height, groupRect.height)
    }

    @MainActor
    func testSwapNodesPreservesDestinationSlotWeights() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let first = TestWindow.new(id: 1, parent: root, adaptiveWeight: 1)
        let second = TestWindow.new(id: 2, parent: root, adaptiveWeight: 3)

        swapNodes(second, first)

        XCTAssertEqual(root.children.first, second)
        XCTAssertEqual(root.children.last, first)
        XCTAssertEqual(second.hWeight, 1)
        XCTAssertEqual(first.hWeight, 3)
    }

    @MainActor
    func testSwapNodesKeepsDraggedSourceMostRecentWhenMovingBackward() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 1, parent: root)
        let source = TestWindow.new(id: 2, parent: root)

        XCTAssertTrue(source.focusWindow())

        swapNodes(source, root.children.first.orDie())

        XCTAssertEqual(root.mostRecentWindowRecursive, source)
    }

    @MainActor
    func testApplyWindowSwapDragIntentFocusesDraggedWindow() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)

        XCTAssertTrue(target.focusWindow())
        XCTAssertTrue(applyWindowSwapDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
        ))

        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testApplyWindowSwapDragIntentFocusesDraggedTabGroupRepresentative() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        let target = TestWindow.new(id: 3, parent: root)

        XCTAssertTrue(target.focusWindow())
        XCTAssertTrue(applyWindowSwapDragIntent(
            sourceWindow: source,
            sourceSubject: .group,
            targetWindow: target,
        ))

        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testApplyWindowSwapDragIntentRejectsDraggingTabGroupOntoItsOwnTab() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)

        XCTAssertFalse(applyWindowSwapDragIntent(
            sourceWindow: source,
            sourceSubject: .group,
            targetWindow: target,
        ))
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tab_group([
                .window(1),
                .window(2),
            ]),
        ]))
    }

    @MainActor
    func testApplyWindowSwapDragIntentRejectsSelfTabGroupTabStripDrags() {
        setUpWorkspacesForTests()
        let previousDetachOrigin = getCurrentMouseTabDetachOrigin()
        setCurrentMouseTabDetachOrigin(.tabStrip)
        defer { setCurrentMouseTabDetachOrigin(previousDetachOrigin) }

        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)

        XCTAssertFalse(applyWindowSwapDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
        ))
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tab_group([
                .window(1),
                .window(2),
            ]),
        ]))
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentWrapsTargetAndPlacesDraggedWindowAbove() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 0, parent: root)
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)

        XCTAssertTrue(target.focusWindow())
        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .above,
        ))

        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([
                .window(1),
                .window(2),
            ]),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentUsesExistingVerticalParentWhenPossible() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        _ = TestWindow.new(id: 0, parent: root)
        let stack = TilingContainer.newVTiles(parent: root, adaptiveWeight: WEIGHT_AUTO)
        let target = TestWindow.new(id: 2, parent: stack)
        let source = TestWindow.new(id: 1, parent: root)

        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .below,
        ))

        XCTAssertTrue(root.children[1] === stack)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tiles([
                .window(2),
                .window(1),
            ]),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentRejectsDraggingTabGroupBesideItsOwnTab() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)

        XCTAssertFalse(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .group,
            targetWindow: target,
            position: .left,
        ))
        assertEquals(root.layoutDescription, .h_tiles([
            .v_tab_group([
                .window(1),
                .window(2),
            ]),
        ]))
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentUsesExistingHorizontalParentToCreateMiddleColumn() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leftStack = TilingContainer.newVTiles(parent: root, adaptiveWeight: WEIGHT_AUTO)
        _ = TestWindow.new(id: 1, parent: leftStack)
        let source = TestWindow.new(id: 2, parent: leftStack)
        let target = TestWindow.new(id: 3, parent: root)

        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .left,
        ))

        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([
                .window(1),
            ]),
            .window(2),
            .window(3),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentUsesExistingHorizontalAncestorForNestedTargetBranch() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leftStack = TilingContainer.newVTiles(parent: root, adaptiveWeight: WEIGHT_AUTO)
        let target = TestWindow.new(id: 1, parent: leftStack)
        let source = TestWindow.new(id: 2, parent: leftStack)
        _ = TestWindow.new(id: 3, parent: root)

        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .left,
        ))

        assertEquals(root.layoutDescription, .h_tiles([
            .window(2),
            .v_tiles([
                .window(1),
            ]),
            .window(3),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentReordersWithinExistingSameAxisParentWhenNeeded() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.changeOrientation(.v)
        let target = TestWindow.new(id: 2, parent: root)
        let sibling = TestWindow.new(id: 3, parent: root)
        let source = TestWindow.new(id: 1, parent: root)

        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .above,
        ))

        assertEquals(root.layoutDescription, .v_tiles([
            .window(1),
            .window(2),
            .window(3),
        ]))
        XCTAssertTrue(root.children[2] === sibling)
    }

    @MainActor
    func testApplyWindowStackSplitDragIntentWrapsTargetAndPlacesDraggedWindowLeft() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.changeOrientation(.v)
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)

        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .left,
        ))

        assertEquals(root.layoutDescription, .v_tiles([
            .h_tiles([
                .window(1),
                .window(2),
            ]),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }
}
