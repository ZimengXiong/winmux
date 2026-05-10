@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    func testUnmanagedTabGroupTabBarUsesActiveWindowFrame() {
        setUpWorkspacesForTests()
        config.enableWindowManagement = false
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let active = TestWindow.new(
            id: 1,
            parent: tabGroup,
            rect: Rect(topLeftX: 40, topLeftY: 60, width: 500, height: 300),
        )
        _ = TestWindow.new(id: 2, parent: tabGroup, rect: Rect(topLeftX: 10, topLeftY: 20, width: 100, height: 100))
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 240, height: 180)
        active.markAsMostRecentChild()

        let tabBarRect = tabGroup.windowTabBarRect.orDie()
        let groupFrameRect = tabGroup.windowTabGroupFrameRect.orDie()

        XCTAssertEqual(tabBarRect.topLeftX, 40)
        XCTAssertEqual(tabBarRect.topLeftY, 60)
        XCTAssertEqual(tabBarRect.width, 500)
        XCTAssertEqual(tabBarRect.height, resolvedWindowTabBarHeight())
        XCTAssertEqual(groupFrameRect.topLeftX, 40)
        XCTAssertEqual(groupFrameRect.topLeftY, 60)
        XCTAssertEqual(groupFrameRect.width, 500)
        XCTAssertEqual(groupFrameRect.height, 300)
    }

    @MainActor
    func testManagedTabGroupLayoutInsetsActiveWindowInsideTabShell() async throws {
        setUpWorkspacesForTests()
        cancelManipulatedWithMouseState()
        clearPendingWindowDragIntent()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = workspace.rootTilingContainer
        tabGroup.layout = .tabGroup
        let active = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        XCTAssertTrue(active.focusWindow())

        try await workspace.layoutWorkspace()

        let groupFrame = try XCTUnwrap(tabGroup.lastAppliedLayoutPhysicalRect)
        let activeFrame = try XCTUnwrap(active.lastAppliedLayoutPhysicalRect)
        let tabBarHeight = resolvedWindowTabBarHeight()

        XCTAssertEqual(activeFrame.topLeftX, groupFrame.topLeftX + windowTabGroupShellHorizontalInset())
        XCTAssertEqual(activeFrame.topLeftY, groupFrame.topLeftY + tabBarHeight)
        XCTAssertEqual(activeFrame.width, groupFrame.width - windowTabGroupShellHorizontalInset() * 2)
        XCTAssertEqual(activeFrame.height, groupFrame.height - tabBarHeight - windowTabGroupShellBottomInset())
    }

    @MainActor
    func testTabGroupResizeChromeFrameDerivesFromActiveWindowContentFrame() {
        config.windowTabs.height = 36
        let activeContentFrame = Rect(topLeftX: 43, topLeftY: 96, width: 494, height: 261)
        let groupFrame = windowTabGroupFrameRect(forActiveWindowContentRect: activeContentFrame)
        let tabBarFrame = windowTabBarRect(forGroupFrameRect: groupFrame)

        XCTAssertEqual(groupFrame.topLeftX, 40)
        XCTAssertEqual(groupFrame.topLeftY, 60)
        XCTAssertEqual(groupFrame.width, 500)
        XCTAssertEqual(groupFrame.height, 300)
        XCTAssertEqual(tabBarFrame.topLeftX, 40)
        XCTAssertEqual(tabBarFrame.topLeftY, 60)
        XCTAssertEqual(tabBarFrame.width, 500)
        XCTAssertEqual(tabBarFrame.height, 36)
    }

    func testTabGroupOuterTopRadiusMatchesTabStripInsteadOfAppWindow() {
        let topInnerRadius = CGFloat(40)
        XCTAssertEqual(windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerRadius), 12)
        XCTAssertLessThan(
            windowTabGroupOuterCornerRadius(innerCornerRadius: topInnerRadius),
            topInnerRadius,
        )
    }

    func testWindowTabLocalOcclusionRectsConvertScreenCoordinatesToPanelCoordinates() {
        let panelFrame = CGRect(x: 100, y: 100, width: 300, height: 200)
        let occludingScreenFrames = [
            CGRect(x: 150, y: 220, width: 80, height: 60),
            CGRect(x: 10, y: 10, width: 20, height: 20),
        ]

        let localRects = windowTabLocalOcclusionRects(
            panelFrame: panelFrame,
            occludingScreenFrames: occludingScreenFrames,
        )

        XCTAssertEqual(localRects, [
            CGRect(x: 50, y: 20, width: 80, height: 60),
        ])
    }

    func testWindowTabStripViewModelTracksFloatingWindowOcclusionSeparatelyForStripAndFrame() {
        let owner = NSObject()
        let model = WindowTabStripViewModel(
            id: ObjectIdentifier(owner),
            workspaceName: "tabs",
            frame: CGRect(x: 100, y: 280, width: 300, height: 28),
            groupFrame: CGRect(x: 100, y: 100, width: 300, height: 208),
            activeWindowId: 1,
            activeWindowCornerRadius: 12,
            tabs: [],
            occludingFloatingWindowFrames: [
                CGRect(x: 140, y: 120, width: 100, height: 80),
            ],
        )

        XCTAssertFalse(model.tabStripIsOccludedByFloatingWindow)
        XCTAssertTrue(model.groupFrameIsOccludedByFloatingWindow)
    }

    @MainActor
    func testWindowSplitZonesWrapCenteredSwapZoneWithoutTouchingTabDropZone() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 360, height: 240)

        let tabInteractionZone = window.tabDropInteractionRect.orDie()
        let leftSplitZone = window.stackSplitDropZoneRect(position: .left).orDie()
        let rightSplitZone = window.stackSplitDropZoneRect(position: .right).orDie()
        let topSplitZone = window.stackSplitDropZoneRect(position: .above).orDie()
        let swapDropZone = window.swapDropZoneRect.orDie()
        let bottomSplitZone = window.stackSplitDropZoneRect(position: .below).orDie()

        XCTAssertGreaterThanOrEqual(topSplitZone.minY, tabInteractionZone.maxY)
        XCTAssertEqual(topSplitZone.maxY, swapDropZone.minY)
        XCTAssertEqual(bottomSplitZone.minY, swapDropZone.maxY)
        XCTAssertEqual(leftSplitZone.maxX, swapDropZone.minX)
        XCTAssertEqual(rightSplitZone.minX, swapDropZone.maxX)
        XCTAssertEqual(topSplitZone.minX, swapDropZone.minX)
        XCTAssertEqual(topSplitZone.maxX, swapDropZone.maxX)
        XCTAssertEqual(bottomSplitZone.minX, swapDropZone.minX)
        XCTAssertEqual(bottomSplitZone.maxX, swapDropZone.maxX)
        XCTAssertLessThan(leftSplitZone.minY, swapDropZone.minY)
        XCTAssertGreaterThan(leftSplitZone.maxY, swapDropZone.maxY)
        XCTAssertLessThan(rightSplitZone.minY, swapDropZone.minY)
        XCTAssertGreaterThan(rightSplitZone.maxY, swapDropZone.maxY)
        XCTAssertTrue(swapDropZone.contains(swapDropZone.center))
    }

    @MainActor
    func testWindowBodyIntentUsesFullHeightSideBandsAndCenteredVerticalBands() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 360, height: 240)

        let swapRect = window.swapDropZoneRect.orDie()

        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: 24, y: 90)), .stackSplit(.left))
        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: 24, y: 210)), .stackSplit(.left))
        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: 336, y: 90)), .stackSplit(.right))
        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: 336, y: 210)), .stackSplit(.right))
        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: swapRect.center.x, y: swapRect.minY - 10)), .stackSplit(.above))
        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: swapRect.center.x, y: swapRect.center.y)), .swap)
        XCTAssertEqual(window.bodyDragIntent(at: CGPoint(x: swapRect.center.x, y: swapRect.maxY + 10)), .stackSplit(.below))
    }

    @MainActor
    func testSplitPreviewRectsStayFlushWithTheInternalSplitSeam() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 10, topLeftY: 20, width: 360, height: 240)

        let fullRect = window.lastAppliedLayoutPhysicalRect.orDie()
        let leftPreview = window.stackSplitPreviewRect(position: .left).orDie()
        let rightPreview = window.stackSplitPreviewRect(position: .right).orDie()
        let topPreview = window.stackSplitPreviewRect(position: .above).orDie()
        let bottomPreview = window.stackSplitPreviewRect(position: .below).orDie()

        XCTAssertEqual(leftPreview.minX, fullRect.minX)
        XCTAssertEqual(leftPreview.maxX, fullRect.minX + fullRect.width / 2)
        XCTAssertEqual(rightPreview.minX, fullRect.minX + fullRect.width / 2)
        XCTAssertEqual(rightPreview.maxX, fullRect.maxX)
        XCTAssertEqual(topPreview.minY, fullRect.minY)
        XCTAssertEqual(topPreview.maxY, fullRect.minY + fullRect.height / 2)
        XCTAssertEqual(bottomPreview.minY, fullRect.minY + fullRect.height / 2)
        XCTAssertEqual(bottomPreview.maxY, fullRect.maxY)
    }

    @MainActor
    func testResolvedSplitPreviewUsesAncestorBranchRectForSameAxisNestedInsertions() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leftStack = TilingContainer.newVTiles(parent: root, adaptiveWeight: WEIGHT_AUTO)
        let target = TestWindow.new(id: 1, parent: leftStack)
        let sibling = TestWindow.new(id: 2, parent: leftStack)
        _ = TestWindow.new(id: 3, parent: root)

        root.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 220)
        leftStack.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 100)
        sibling.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 100, width: 200, height: 120)

        let preview = resolvedWindowStackSplitPreview(targetNode: target.moveNode, position: .right).orDie()

        XCTAssertEqual(preview.geometry, .splitRight)
        XCTAssertEqual(preview.rect.minX, 100)
        XCTAssertEqual(preview.rect.maxX, 200)
        XCTAssertEqual(preview.rect.minY, 0)
        XCTAssertEqual(preview.rect.maxY, 220)
        XCTAssertGreaterThan(preview.rect.height, target.lastAppliedLayoutPhysicalRect.orDie().height)
    }

    @MainActor
    func testResolvedSplitPreviewUsesVisibleBranchBoundsWhenSiblingOverflowsLayoutSlot() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leftStack = TilingContainer.newVTiles(parent: root, adaptiveWeight: WEIGHT_AUTO)
        let target = TestWindow.new(id: 1, parent: leftStack)
        let overflowingSibling = TestWindow.new(id: 2, parent: leftStack)
        _ = TestWindow.new(id: 3, parent: root)

        root.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 220)
        leftStack.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 100)
        overflowingSibling.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 100, width: 200, height: 120)
        target.lastKnownActualRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 100)
        overflowingSibling.lastKnownActualRect = Rect(topLeftX: 0, topLeftY: 100, width: 260, height: 120)

        let preview = resolvedWindowStackSplitPreview(targetNode: target.moveNode, position: .right).orDie()

        XCTAssertEqual(preview.geometry, .splitRight)
        XCTAssertEqual(preview.rect.minX, 130)
        XCTAssertEqual(preview.rect.maxX, 260)
        XCTAssertEqual(preview.rect.minY, 0)
        XCTAssertEqual(preview.rect.maxY, 220)
    }

    @MainActor
    func testResolveWindowDragActualRectKeepsCachedOverflowWhenCandidateMatchesLayout() {
        let cached = Rect(topLeftX: 180, topLeftY: 0, width: 260, height: 220)
        let layout = Rect(topLeftX: 180, topLeftY: 0, width: 200, height: 220)

        let resolved = resolveWindowDragActualRect(cached: cached, candidate: layout, layout: layout)

        XCTAssertEqual(resolved.minX, 180)
        XCTAssertEqual(resolved.maxX, 440)
    }

    @MainActor
    func testWindowDragTargetLookupCanExcludeDraggedSourceWindowFromOverlapHitTesting() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 180, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 180, topLeftY: 0, width: 180, height: 220)
        source.lastKnownActualRect = Rect(topLeftX: 0, topLeftY: 0, width: 240, height: 220)
        target.lastKnownActualRect = Rect(topLeftX: 180, topLeftY: 0, width: 180, height: 220)
        source.markAsMostRecentChild()

        let overlapPoint = CGPoint(x: 200, y: 110)

        XCTAssertTrue(overlapPoint.findWindowDragTarget(in: root) === source)
        XCTAssertTrue(overlapPoint.findWindowDragTarget(in: root, excluding: source) === target)
    }

    @MainActor
    func testTabInsertPreviewRectStaysFlushWithBottomEdgeOfTabBand() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 10, topLeftY: 20, width: 360, height: 240)

        let fullRect = window.lastAppliedLayoutPhysicalRect.orDie()
        let tabPreview = window.tabDropZoneRect.orDie()
        let expectedTabBandHeight = min(max(resolvedWindowTabBarHeight() + 18, 52), fullRect.height)

        XCTAssertEqual(tabPreview.minX, fullRect.minX)
        XCTAssertEqual(tabPreview.maxX, fullRect.maxX)
        XCTAssertEqual(tabPreview.minY, fullRect.minY)
        XCTAssertEqual(tabPreview.maxY, fullRect.minY + expectedTabBandHeight)
    }

    @MainActor
    func testWindowStackSplitAvailabilityAlwaysOffersAllFourBodyDirections() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.changeOrientation(.v)
        let target = TestWindow.new(id: 1, parent: root)
        let source = TestWindow.new(id: 2, parent: root)

        XCTAssertTrue(canOfferWindowStackSplit(
            sourceNode: source,
            targetNode: target,
            position: .above,
        ))
        XCTAssertTrue(canOfferWindowStackSplit(
            sourceNode: source,
            targetNode: target,
            position: .below,
        ))
        XCTAssertTrue(canOfferWindowStackSplit(
            sourceNode: source,
            targetNode: target,
            position: .left,
        ))
        XCTAssertTrue(canOfferWindowStackSplit(
            sourceNode: source,
            targetNode: target,
            position: .right,
        ))
    }

    @MainActor
    func testWindowStackSplitAvailabilityAllowsMiddleColumnFromDifferentBranch() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leftStack = TilingContainer.newVTiles(parent: root, adaptiveWeight: WEIGHT_AUTO)
        _ = TestWindow.new(id: 1, parent: leftStack)
        let source = TestWindow.new(id: 2, parent: leftStack)
        let target = TestWindow.new(id: 3, parent: root)

        XCTAssertTrue(canOfferWindowStackSplit(
            sourceNode: source,
            targetNode: target,
            position: .left,
        ))
        XCTAssertTrue(canOfferWindowStackSplit(
            sourceNode: source,
            targetNode: target,
            position: .right,
        ))
    }

    @MainActor
    func testTabDetachKeepRectsDifferentiateWindowAndTabStripDrags() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
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
    func testSameTabGroupTabInsertTargetIsSuppressedForDetachDrags() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)

        XCTAssertTrue(shouldSuppressSameTabGroupTabDestination(
            sourceWindow: source,
            targetWindow: target,
            detachOrigin: .window,
        ))
        XCTAssertTrue(shouldSuppressSameTabGroupTabDestination(
            sourceWindow: source,
            targetWindow: target,
            detachOrigin: .tabStrip,
        ))
    }
}
