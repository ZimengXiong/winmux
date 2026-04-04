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
            .window(1),
            .window(2),
        ]))
    }

    @MainActor
    func testRemoveWindowFromNestedTwoTabStackFlattensDeadAccordion() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let remaining = TestWindow.new(id: 1, parent: stack)
        let removed = TestWindow.new(id: 2, parent: stack)

        XCTAssertTrue(removeWindowFromTabStack(removed))

        XCTAssertTrue(remaining.parent === root)
        XCTAssertTrue(remaining.moveNode === remaining)
        XCTAssertFalse(root.children.contains(where: { $0 === stack }))
    }

    @MainActor
    func testRemoveWindowFromRootTabStackPreservesRemainingActiveTab() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        let removed = TestWindow.new(id: 1, parent: root)
        let expectedActive = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)
        expectedActive.markAsMostRecentChild()

        XCTAssertTrue(removeWindowFromTabStack(removed))

        let rebuiltAccordion = root.children.first as? TilingContainer
        XCTAssertNotNil(rebuiltAccordion)
        XCTAssertEqual(rebuiltAccordion?.layout, .accordion)
        XCTAssertEqual(rebuiltAccordion?.tabActiveWindow, expectedActive)
    }

    @MainActor
    func testFocusAfterWindowClosurePrefersPreviousActiveTabOverMacOsFallback() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        _ = TestWindow.new(id: 3, parent: accordion)
        let expectedTab = TestWindow.new(id: 4, parent: accordion)
        let closingWindow = TestWindow.new(id: 9, parent: workspace)

        XCTAssertTrue(expectedTab.focusWindow())
        let previousFocus = focus

        XCTAssertTrue(closingWindow.focusWindow())

        // Simulate macOS surfacing a different tab in the same group before GC runs.
        XCTAssertTrue(firstTab.focusWindow())

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: focus,
            previousFocus: previousFocus,
            previousPreviousFocus: nil,
            refreshSnapshotCloseFallback: nil,
            refreshSnapshotPreviousFocus: nil,
            refreshSnapshotPreviousPreviousFocus: nil,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: .now,
        )

        XCTAssertEqual(replacementFocus?.windowOrNil, expectedTab)
    }

    @MainActor
    func testFocusAfterWindowClosureUsesRefreshSnapshotWhenPrevFocusWasOverwritten() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        _ = TestWindow.new(id: 3, parent: accordion)
        let expectedTab = TestWindow.new(id: 4, parent: accordion)
        let closingWindow = TestWindow.new(id: 9, parent: workspace)

        XCTAssertTrue(expectedTab.focusWindow())
        let snapshotPreviousFocus = focus

        XCTAssertTrue(closingWindow.focusWindow())
        XCTAssertTrue(firstTab.focusWindow())

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: focus,
            previousFocus: closingWindow.toLiveFocusOrNil(),
            previousPreviousFocus: nil,
            refreshSnapshotCloseFallback: nil,
            refreshSnapshotPreviousFocus: snapshotPreviousFocus,
            refreshSnapshotPreviousPreviousFocus: nil,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: .now,
        )

        XCTAssertEqual(replacementFocus?.windowOrNil, expectedTab)
    }

    @MainActor
    func testFocusAfterWindowClosureFallsBackToPreviousPreviousFocusAfterInterimFallbackFocus() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        _ = TestWindow.new(id: 3, parent: accordion)
        let expectedTab = TestWindow.new(id: 4, parent: accordion)
        let closingWindow = TestWindow.new(id: 9, parent: workspace)

        XCTAssertTrue(expectedTab.focusWindow())
        XCTAssertTrue(closingWindow.focusWindow())
        XCTAssertTrue(firstTab.focusWindow())

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: focus,
            previousFocus: closingWindow.toLiveFocusOrNil(),
            previousPreviousFocus: expectedTab.toLiveFocusOrNil(),
            refreshSnapshotCloseFallback: nil,
            refreshSnapshotPreviousFocus: nil,
            refreshSnapshotPreviousPreviousFocus: nil,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: .now,
        )

        XCTAssertEqual(replacementFocus?.windowOrNil, expectedTab)
    }

    @MainActor
    func testFocusAfterWindowClosureUsesPreFallbackWorkspaceCandidateWhenHistoryIsStale() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        _ = TestWindow.new(id: 3, parent: accordion)
        let expectedTab = TestWindow.new(id: 4, parent: accordion)
        let closingWindow = TestWindow.new(id: 9, parent: workspace)

        XCTAssertTrue(expectedTab.focusWindow())
        let closeFallback = workspace.toLiveFocus(excluding: closingWindow)

        XCTAssertTrue(closingWindow.focusWindow())
        XCTAssertTrue(firstTab.focusWindow())

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: focus,
            previousFocus: nil,
            previousPreviousFocus: nil,
            refreshSnapshotCloseFallback: closeFallback,
            refreshSnapshotPreviousFocus: nil,
            refreshSnapshotPreviousPreviousFocus: nil,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: .now,
        )

        XCTAssertEqual(replacementFocus?.windowOrNil, expectedTab)
    }

    @MainActor
    func testFocusAfterWindowClosurePrefersSnapshotCloseFallbackOverProvisionalSameAppFocus() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let expectedTab = TestWindow.new(id: 1, parent: root)
        let provisionalSameAppFocus = TestWindow.new(id: 2, parent: root)
        let closingWindow = TestWindow.new(id: 3, parent: workspace)

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: provisionalSameAppFocus.toLiveFocusOrNil().orDie(),
            previousFocus: nil,
            previousPreviousFocus: expectedTab.toLiveFocusOrNil(),
            refreshSnapshotCloseFallback: expectedTab.toLiveFocusOrNil(),
            refreshSnapshotPreviousFocus: provisionalSameAppFocus.toLiveFocusOrNil(),
            refreshSnapshotPreviousPreviousFocus: expectedTab.toLiveFocusOrNil(),
            previousFocusedWorkspace: workspace,
            previousFocusedWorkspaceDate: .now,
        )

        XCTAssertEqual(replacementFocus?.windowOrNil, expectedTab)
    }

    @MainActor
    func testFocusAfterWindowClosurePrefersSnapshotPreviousFocusOverFallbackTabInSameGroup() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let staleFallbackTab = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        let expectedTab = TestWindow.new(id: 3, parent: accordion)
        let closingWindow = TestWindow.new(id: 9, parent: workspace)

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: staleFallbackTab.toLiveFocusOrNil().orDie(),
            previousFocus: nil,
            previousPreviousFocus: nil,
            refreshSnapshotCloseFallback: staleFallbackTab.toLiveFocusOrNil(),
            refreshSnapshotPreviousFocus: expectedTab.toLiveFocusOrNil(),
            refreshSnapshotPreviousPreviousFocus: nil,
            previousFocusedWorkspace: workspace,
            previousFocusedWorkspaceDate: .now,
        )

        XCTAssertEqual(replacementFocus?.windowOrNil, expectedTab)
    }

    func testNativeFocusShortcutIsDisabledForTabbedLogicalWindows() {
        XCTAssertFalse(shouldUseActivationOnlyForNativeFocus(
            targetWindowId: 4,
            lastNativeFocusedWindowId: 1,
            logicalWindowsCount: 4,
        ))
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
    func testWindowSplitZonesWrapCenteredSwapZoneWithoutTouchingTabDropZone() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 360, height: 240)

        let tabInteractionZone = window.tabDropInteractionRect.orDie()
        let topSplitZone = window.stackSplitDropZoneRect(position: .above).orDie()
        let swapDropZone = window.swapDropZoneRect.orDie()
        let bottomSplitZone = window.stackSplitDropZoneRect(position: .below).orDie()

        XCTAssertGreaterThan(topSplitZone.minY, tabInteractionZone.maxY)
        XCTAssertEqual(topSplitZone.maxY, swapDropZone.minY)
        XCTAssertEqual(bottomSplitZone.minY, swapDropZone.maxY)
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
        XCTAssertLessThanOrEqual(windowKeepRect.minX, window.lastAppliedLayoutPhysicalRect.orDie().minX)
        XCTAssertGreaterThanOrEqual(windowKeepRect.maxX, window.lastAppliedLayoutPhysicalRect.orDie().maxX)
        XCTAssertLessThanOrEqual(windowKeepRect.topLeftY, window.lastAppliedLayoutPhysicalRect.orDie().topLeftY)
    }

    @MainActor
    func testSameAccordionTabInsertTargetIsSuppressedForDetachDrags() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: accordion)
        let target = TestWindow.new(id: 2, parent: accordion)

        XCTAssertTrue(shouldSuppressSameAccordionTabDestination(
            sourceWindow: source,
            targetWindow: target,
            detachOrigin: .window,
        ))
        XCTAssertTrue(shouldSuppressSameAccordionTabDestination(
            sourceWindow: source,
            targetWindow: target,
            detachOrigin: .tabStrip,
        ))
    }

    @MainActor
    func testResolvedDraggedWindowAnchorRectUsesWholeGroupForGroupDrag() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        let windowRect = Rect(topLeftX: 12, topLeftY: 40, width: 300, height: 220)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 260)
        window.lastAppliedLayoutPhysicalRect = windowRect
        accordion.lastAppliedLayoutPhysicalRect = groupRect

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
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        let windowRect = Rect(topLeftX: 12, topLeftY: 40, width: 300, height: 220)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 260)
        window.lastAppliedLayoutPhysicalRect = windowRect
        accordion.lastAppliedLayoutPhysicalRect = groupRect

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
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        let groupRect = Rect(topLeftX: 0, topLeftY: 0, width: 320, height: 260)
        accordion.lastAppliedLayoutPhysicalRect = groupRect

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
        let accordion = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
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
        _ = TestWindow.new(id: 3, parent: stack)
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
                .window(3),
            ]),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testWorkspaceMoveBindingDataWrapsRootAccordionInsteadOfTargetingWorkspace() {
        setUpWorkspacesForTests()
        let targetWorkspace = Workspace.get(byName: "target")
        let rootAccordion = targetWorkspace.rootTilingContainer
        rootAccordion.layout = .accordion
        if rootAccordion.orientation != .h {
            rootAccordion.changeOrientation(.h)
        }
        let target = TestWindow.new(id: 10, parent: rootAccordion)
        _ = TestWindow.new(id: 11, parent: rootAccordion)
        rootAccordion.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 600, height: 400)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 600, height: 366)

        let binding = workspaceMoveBindingData(
            targetWorkspace: targetWorkspace,
            swapTarget: target,
            mouseLocation: CGPoint(x: 500, y: 350),
        )

        XCTAssertTrue(binding.parent === targetWorkspace.rootTilingContainer)
        XCTAssertEqual(targetWorkspace.rootTilingContainer.layout, .tiles)
        XCTAssertEqual(targetWorkspace.rootTilingContainer.children.count, 1)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === rootAccordion)
        XCTAssertEqual(binding.index, 1)
        XCTAssertTrue(targetWorkspace.floatingWindows.isEmpty)
    }

    @MainActor
    func testWorkspaceAppendBindingDataWrapsRootAccordionInsteadOfAppendingAsTab() {
        setUpWorkspacesForTests()
        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        let targetWorkspace = Workspace.get(byName: "target")
        let rootAccordion = targetWorkspace.rootTilingContainer
        rootAccordion.layout = .accordion
        _ = TestWindow.new(id: 10, parent: rootAccordion)
        _ = TestWindow.new(id: 11, parent: rootAccordion)

        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        source.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)

        XCTAssertEqual(targetWorkspace.rootTilingContainer.layout, .tiles)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === rootAccordion)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.last === source)
        XCTAssertEqual(rootAccordion.children.count, 2)
    }

    @MainActor
    func testWorkspaceMoveBindingDataWithoutSwapTargetAppendsInsteadOfPrepending() {
        setUpWorkspacesForTests()
        let targetWorkspace = Workspace.get(byName: "target")
        let first = TestWindow.new(id: 10, parent: targetWorkspace.rootTilingContainer)
        let second = TestWindow.new(id: 11, parent: targetWorkspace.rootTilingContainer)

        let binding = workspaceMoveBindingData(
            targetWorkspace: targetWorkspace,
            swapTarget: nil,
            mouseLocation: CGPoint(x: 999, y: 999),
        )
        let source = TestWindow.new(id: 1, parent: Workspace.get(byName: "source").rootTilingContainer)
        source.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)

        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === first)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children[targetWorkspace.rootTilingContainer.children.count - 2] === second)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.last === source)
    }

    func testStickyWindowDragIntentDisabledForDetachPreview() {
        XCTAssertFalse(shouldUseStickyWindowDragIntent(previewStyle: .detach))
    }

    func testStickyWindowDragIntentEnabledForTabInsertAndSwapPreviews() {
        XCTAssertTrue(shouldUseStickyWindowDragIntent(previewStyle: .tabInsert))
        XCTAssertTrue(shouldUseStickyWindowDragIntent(previewStyle: .stackSplit))
        XCTAssertTrue(shouldUseStickyWindowDragIntent(previewStyle: .swap))
        XCTAssertFalse(shouldUseStickyWindowDragIntent(previewStyle: .workspaceMove))
        XCTAssertFalse(shouldUseStickyWindowDragIntent(previewStyle: .sidebarWorkspaceMove))
    }

    @MainActor
    func testTabInsertWindowDragIntentKindTracksWindowTabsFeatureFlag() {
        config.windowTabs.enabled = true
        XCTAssertTrue(isWindowDragIntentKindEnabled(.tabStack(targetWindowId: 1)))

        config.windowTabs.enabled = false
        XCTAssertFalse(isWindowDragIntentKindEnabled(.tabStack(targetWindowId: 1)))
        XCTAssertTrue(isWindowDragIntentKindEnabled(.swap(targetWindowId: 1)))
    }

    @MainActor
    func testBeginWindowMoveSessionPreservesAnchorRectAcrossRepeatedCallbacks() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()
        let workspace = Workspace.get(byName: "tabs")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .accordion, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: accordion)
        _ = TestWindow.new(id: 2, parent: accordion)
        let groupRect = Rect(topLeftX: 5, topLeftY: 7, width: 320, height: 240)

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: window.windowId,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: true,
            anchorRect: groupRect,
        ))
        XCTAssertFalse(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: window.windowId,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: true,
            anchorRect: nil,
        ))

        let preservedRect = draggedWindowAnchorRect(for: window.windowId).orDie()
        XCTAssertEqual(preservedRect.topLeftX, groupRect.topLeftX)
        XCTAssertEqual(preservedRect.topLeftY, groupRect.topLeftY)
        XCTAssertEqual(preservedRect.width, groupRect.width)
        XCTAssertEqual(preservedRect.height, groupRect.height)
    }

    @MainActor
    func testBeginWindowMoveSessionClearsPreviousWindowAnchorWhenDragSourceChanges() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()
        let workspace = Workspace.get(byName: "tabs")
        let firstWindow = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let secondWindow = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: firstWindow.windowId,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 120),
        ))
        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: secondWindow.windowId,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: Rect(topLeftX: 20, topLeftY: 24, width: 180, height: 100),
        ))

        XCTAssertNil(draggedWindowAnchorRect(for: firstWindow.windowId))
        XCTAssertNotNil(draggedWindowAnchorRect(for: secondWindow.windowId))
    }

    @MainActor
    func testStickySwapHintDoesNotSurviveTargetRemoval() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = target.swapDropZoneRect.orDie().center

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))

        target.unbindFromParent()

        XCTAssertFalse(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))
    }

    @MainActor
    func testStickySwapHintDoesNotSurviveTargetGeometryChanges() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = target.swapDropZoneRect.orDie().center

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))

        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 520, topLeftY: 0, width: 200, height: 220)

        XCTAssertFalse(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))
    }

    @MainActor
    func testStickyTabInsertHintDoesNotSurviveTargetRemoval() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        root.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 220)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = target.tabDropInteractionRect.orDie().center

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))

        target.unbindFromParent()

        XCTAssertFalse(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))
    }

    @MainActor
    func testStickyTabInsertHintDoesNotSurviveTargetGeometryChanges() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        root.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 220)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = target.tabDropInteractionRect.orDie().center

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))

        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 520, topLeftY: 0, width: 200, height: 220)

        XCTAssertFalse(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))
    }

    @MainActor
    func testStickyTabInsertHintDoesNotSurviveWindowTabsBeingDisabled() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        root.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 220)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)
        let mouseLocation = target.tabDropInteractionRect.orDie().center

        XCTAssertTrue(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))

        config.windowTabs.enabled = false

        XCTAssertFalse(updatePendingWindowDragIntent(sourceWindow: source, mouseLocation: mouseLocation))
    }

    @MainActor
    func testWindowTabStripGroupDragDefersToDetachedTabDrag() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertTrue(shouldDeferWindowTabStripGroupDragToDetachedTabDrag())
    }

    @MainActor
    func testWindowTabStripGroupDragEndIsIgnoredForDetachedTabDrags() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertFalse(shouldHandleWindowTabStripGroupDragEnd())
    }

    @MainActor
    func testWindowTabStripGroupDragEndRunsForGroupDrags() {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()

        XCTAssertTrue(beginWindowMoveWithMouseSessionIfNeeded(
            windowId: 42,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
            anchorRect: nil,
        ))

        XCTAssertTrue(shouldHandleWindowTabStripGroupDragEnd())
    }

    func testWindowTabStripDragInProgressRecognizesDetachedTabDrag() {
        XCTAssertTrue(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .window,
            detachOrigin: .tabStrip,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripDragInProgressRecognizesGroupDrag() {
        XCTAssertTrue(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripDragInProgressIgnoresRegularWindowMove() {
        XCTAssertFalse(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .window,
            detachOrigin: .window,
            startedInSidebar: false,
        ))
        XCTAssertFalse(isWindowTabStripDragInProgress(
            kind: .move,
            subject: .group,
            detachOrigin: .window,
            startedInSidebar: true,
        ))
    }

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

    func testMovedObsIgnoresManagedGroupDragSession() {
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
