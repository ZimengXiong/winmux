@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    func testCrossWorkspaceMoveHintStillWorks() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let main = WindowTabsTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WindowTabsTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { clearPendingWindowDragIntent() }

        let sourceWorkspace = Workspace.get(byName: "source")
        XCTAssertTrue(sourceWorkspace.focusWorkspace())
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)

        let targetWorkspace = Workspace.get(byName: "target")
        targetWorkspace.seedMonitorIfNeeded(secondary)
        XCTAssertTrue(secondary.setActiveWorkspace(targetWorkspace))
        let mouseLocation = targetWorkspace.workspaceMonitor.visibleRectPaddedByOuterGaps.center

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: mouseLocation,
            subject: .window,
            detachOrigin: .window,
        ))

        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .moveToWorkspace(workspaceName: targetWorkspace.name))
    }

    @MainActor
    func testCrossWorkspaceDragOverTargetWindowOffersSurfaceIntent() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 220, height: 180)

        let targetWorkspace = Workspace.get(byName: "target")
        let target = TestWindow.new(id: 2, parent: targetWorkspace.rootTilingContainer)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 120, topLeftY: 80, width: 420, height: 300)
        XCTAssertTrue(targetWorkspace.focusWorkspace())

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: target.stackSplitDropZoneRect(position: .left).orDie().center,
            subject: .window,
            detachOrigin: .window,
        ))

        XCTAssertEqual(
            debugPendingWindowDragIntentSummary()?.kind,
            .stackSplit(targetWindowId: target.windowId, position: .left)
        )
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

    func testTabStripOriginatedDragKeepsTabStripMouseEventsEnabled() {
        XCTAssertFalse(shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: .tabStrip))
        XCTAssertTrue(shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: .window))
    }

    func testTabStripReentryTargetIndexTracksPointerPosition() {
        let stripRect = Rect(topLeftX: 100, topLeftY: 20, width: 420, height: 44)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripRect.width, count: 3)
        let firstTabMinX = stripRect.minX + windowTabStripContentHorizontalPadding
        let secondTabCenterX = firstTabMinX + tabWidth + windowTabStripTabSpacing + tabWidth / 2

        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: 120, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 0),
            0
        )
        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: secondTabCenterX - 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 0),
            0
        )
        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: secondTabCenterX + 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 0),
            1
        )
    }

    func testTabStripReentryTargetIndexAdjustsForSourceRemovalWhenDraggingBackward() {
        let stripRect = Rect(topLeftX: 100, topLeftY: 20, width: 420, height: 44)
        let tabWidth = windowTabStripTabWidth(stripWidth: stripRect.width, count: 3)
        let firstTabCenterX = stripRect.minX + windowTabStripContentHorizontalPadding + tabWidth / 2

        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: firstTabCenterX - 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 2),
            0
        )
        XCTAssertEqual(
            tabReentryTargetIndex(mouseLocation: CGPoint(x: firstTabCenterX + 1, y: 40), tabStripRect: stripRect, tabCount: 3, sourceIndex: 2),
            1
        )
    }

    func testTabStripReentrySourceVisualOffsetTracksPointerSmoothly() {
        let stripRect = Rect(topLeftX: 100, topLeftY: 20, width: 420, height: 54)
        let middle = tabReentrySourceVisualOffset(
            mouseLocation: CGPoint(x: 310, y: 40),
            tabStripRect: stripRect,
            tabCount: 3,
            sourceIndex: 1
        )
        let right = tabReentrySourceVisualOffset(
            mouseLocation: CGPoint(x: 350, y: 40),
            tabStripRect: stripRect,
            tabCount: 3,
            sourceIndex: 1
        )

        XCTAssertGreaterThan(right, middle)
    }

    @MainActor
    func testDetachedTabReentryReordersWithinCurrentTabGroup() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 1, parent: tabGroup)
        let second = TestWindow.new(id: 2, parent: tabGroup)
        let third = TestWindow.new(id: 3, parent: tabGroup)

        XCTAssertTrue(reorderWindowTabInCurrentGroup(third, toIndex: 1))
        XCTAssertEqual(tabGroup.children.compactMap { ($0 as? Window)?.windowId }, [first.windowId, third.windowId, second.windowId])
    }

    func testCompositedGroupPreviewOnlyRunsForTabStripOriginatedGroupDrags() {
        XCTAssertTrue(shouldShowCompositedGroupMovePreview(
            subject: .group,
            startedInSidebar: false,
        ))
        XCTAssertFalse(shouldShowCompositedGroupMovePreview(
            subject: .group,
            startedInSidebar: true,
        ))
        XCTAssertFalse(shouldShowCompositedGroupMovePreview(
            subject: .window,
            startedInSidebar: false,
        ))
    }

    func testWindowTabStripLayoutMatchesNextChromeMetrics() {
        let stripWidth: CGFloat = 360
        let expectedViewportWidth = stripWidth
            - 16
            - windowTabStripReservedGroupHandleWidth()
            - windowTabStripTrailingGroupDragGutterWidth
            - 18
        let expectedTabsWidth = expectedViewportWidth
            - (windowTabStripContentPadding() * 2)

        XCTAssertEqual(windowTabStripScrollViewportWidth(stripWidth: stripWidth), expectedViewportWidth)
        XCTAssertEqual(windowTabStripAvailableTabsWidth(stripWidth: stripWidth), expectedTabsWidth)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: stripWidth, count: 1), 240)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: stripWidth, count: 2), 132)
        XCTAssertEqual(windowTabStripTabWidth(stripWidth: stripWidth, count: 3), windowTabStripMinimumTabWidth)
        XCTAssertLessThanOrEqual(
            CGFloat(2) * windowTabStripTabWidth(stripWidth: stripWidth, count: 2)
                + windowTabStripTabSpacing
                + windowTabStripContentPadding() * 2,
            windowTabStripScrollViewportWidth(stripWidth: stripWidth)
        )
        XCTAssertGreaterThan(
            CGFloat(3) * windowTabStripTabWidth(stripWidth: stripWidth, count: 3)
                + CGFloat(2) * windowTabStripTabSpacing
                + windowTabStripContentPadding() * 2,
            windowTabStripScrollViewportWidth(stripWidth: stripWidth)
        )
        XCTAssertLessThan(windowTabStripAvailableTabsWidth(stripWidth: stripWidth), stripWidth)
    }

    func testWindowTabStripScrollBackgroundDragIgnoresTabPills() {
        let tabWidth: CGFloat = 120
        let tabsStart = windowTabStripContentHorizontalPadding
        let tabsEnd = tabsStart + tabWidth * 2 + windowTabStripTabSpacing

        XCTAssertFalse(isWindowTabStripScrollBackgroundDragStart(
            localX: tabsStart + 12,
            contentMinX: 0,
            tabWidth: tabWidth,
            tabCount: 2,
        ))
        XCTAssertFalse(isWindowTabStripScrollBackgroundDragStart(
            localX: tabsEnd - 12,
            contentMinX: 0,
            tabWidth: tabWidth,
            tabCount: 2,
        ))
        XCTAssertTrue(isWindowTabStripScrollBackgroundDragStart(
            localX: tabsEnd + 12,
            contentMinX: 0,
            tabWidth: tabWidth,
            tabCount: 2,
        ))
    }

    func testWindowTabStripLeadingFadeOnlyAppearsAfterScrollingFromLeftEdge() {
        let stripWidth: CGFloat = 240

        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: 0,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: -windowTabStripContentHorizontalPadding - 0.5,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabLeadingScrollFadeWidth(
            isScrollable: false,
            contentMinX: -12,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertGreaterThan(windowTabLeadingScrollFadeWidth(
            isScrollable: true,
            contentMinX: -windowTabStripContentHorizontalPadding - 2,
            stripWidth: stripWidth,
        ), 0)
    }

    func testWindowTabStripTrailingFadeTracksScrollableContent() {
        let stripWidth: CGFloat = 240
        let viewportWidth: CGFloat = 180

        XCTAssertEqual(windowTabTrailingScrollFadeWidth(
            isScrollable: false,
            contentMaxX: viewportWidth + 24,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabTrailingScrollFadeWidth(
            isScrollable: true,
            contentMaxX: viewportWidth,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertEqual(windowTabTrailingScrollFadeWidth(
            isScrollable: true,
            contentMaxX: viewportWidth + windowTabStripContentHorizontalPadding + 0.5,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
        XCTAssertGreaterThan(windowTabTrailingScrollFadeWidth(
            isScrollable: true,
            contentMaxX: viewportWidth + windowTabStripContentHorizontalPadding + 2,
            viewportWidth: viewportWidth,
            stripWidth: stripWidth,
        ), 0)
    }

    @MainActor
    func testHudPanelBaseDoesNotPaintSystemHudBackdrop() {
        let panel = NSPanelHud()

        XCTAssertFalse(panel.styleMask.contains(.hudWindow))
        XCTAssertFalse(panel.isOpaque)
    }

    @MainActor
    func testResizePreviewWeightMapDoesNotMutateWeightsUntilCommit() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.changeOrientation(.h)
        root.layout = .tiles

        let left = TestWindow.new(id: 1, parent: root, adaptiveWeight: 500)
        let right = TestWindow.new(id: 2, parent: root, adaptiveWeight: 500)
        left.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 500, height: 400)
        left.lastAppliedLayoutVirtualRect = left.lastAppliedLayoutPhysicalRect
        right.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 500, topLeftY: 0, width: 500, height: 400)
        right.lastAppliedLayoutVirtualRect = right.lastAppliedLayoutPhysicalRect

        let proposedRect = Rect(topLeftX: 0, topLeftY: 0, width: 620, height: 400)
        let weightMap = proposedResizeWeightMap(left, rect: proposedRect).orDie()

        XCTAssertEqual(left.hWeight, 500)
        XCTAssertEqual(right.hWeight, 500)
        XCTAssertEqual(weightMap.weight(for: left, orientation: .h), 620)
        XCTAssertEqual(weightMap.weight(for: right, orientation: .h), 380)

        applyResizeWithMouse(left, rect: proposedRect)

        XCTAssertEqual(left.hWeight, 620)
        XCTAssertEqual(right.hWeight, 380)
        cancelManipulatedWithMouseState()
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

}
