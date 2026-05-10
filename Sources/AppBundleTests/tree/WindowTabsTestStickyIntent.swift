@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

@MainActor extension WindowTabsTest {
    func testApplyWindowStackSplitDragIntentSupportsRootTabGroupSelfTarget() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.layout = .tabGroup
        root.changeOrientation(.v)
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)
        let previousDetachOrigin = getCurrentMouseTabDetachOrigin()
        setCurrentMouseTabDetachOrigin(.tabStrip)
        defer { setCurrentMouseTabDetachOrigin(previousDetachOrigin) }

        XCTAssertTrue(applyWindowStackSplitDragIntent(
            sourceWindow: source,
            sourceSubject: .window,
            targetWindow: target,
            position: .left,
        ))

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
            .v_tab_group([
                .window(2),
                .window(3),
            ]),
        ]))
        XCTAssertEqual(focus.windowOrNil, source)
    }

    @MainActor
    func testWorkspaceMoveBindingDataWrapsRootTabGroupInsteadOfTargetingWorkspace() {
        setUpWorkspacesForTests()
        let targetWorkspace = Workspace.get(byName: "target")
        let rootTabGroup = targetWorkspace.rootTilingContainer
        rootTabGroup.layout = .tabGroup
        if rootTabGroup.orientation != .h {
            rootTabGroup.changeOrientation(.h)
        }
        let target = TestWindow.new(id: 10, parent: rootTabGroup)
        _ = TestWindow.new(id: 11, parent: rootTabGroup)
        rootTabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 600, height: 400)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 600, height: 366)

        let binding = workspaceMoveBindingData(
            targetWorkspace: targetWorkspace,
            swapTarget: target,
            mouseLocation: CGPoint(x: 500, y: 350),
        )

        XCTAssertTrue(binding.parent === targetWorkspace.rootTilingContainer)
        XCTAssertEqual(targetWorkspace.rootTilingContainer.layout, .tiles)
        XCTAssertEqual(targetWorkspace.rootTilingContainer.children.count, 1)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === rootTabGroup)
        XCTAssertEqual(binding.index, 1)
        XCTAssertTrue(targetWorkspace.floatingWindows.isEmpty)
    }

    @MainActor
    func testWorkspaceAppendBindingDataWrapsRootTabGroupInsteadOfAppendingAsTab() {
        setUpWorkspacesForTests()
        let sourceWorkspace = Workspace.get(byName: "source")
        let source = TestWindow.new(id: 1, parent: sourceWorkspace.rootTilingContainer)
        let targetWorkspace = Workspace.get(byName: "target")
        let rootTabGroup = targetWorkspace.rootTilingContainer
        rootTabGroup.layout = .tabGroup
        _ = TestWindow.new(id: 10, parent: rootTabGroup)
        _ = TestWindow.new(id: 11, parent: rootTabGroup)

        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: INDEX_BIND_LAST)
        source.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)

        XCTAssertEqual(targetWorkspace.rootTilingContainer.layout, .tiles)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.first === rootTabGroup)
        XCTAssertTrue(targetWorkspace.rootTilingContainer.children.last === source)
        XCTAssertEqual(rootTabGroup.children.count, 2)
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
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
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
    func testGroupDragDoesNotOfferSwapHintAgainstItsOwnTab() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        XCTAssertFalse(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: target.swapDropZoneRect.orDie().center,
            subject: .group,
            detachOrigin: .window,
        ))
        XCTAssertNil(debugPendingWindowDragIntentSummary())
    }

    @MainActor
    func testGroupDragDoesNotOfferSplitHintAgainstItsOwnTab() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        defer { clearPendingWindowDragIntent() }

        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        XCTAssertFalse(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: target.stackSplitDropZoneRect(position: .left).orDie().center,
            subject: .group,
            detachOrigin: .window,
        ))
        XCTAssertNil(debugPendingWindowDragIntentSummary())
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
    func testUnmanagedSameWorkspaceBodyMoveHintIsSuppressed() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let previousValue = config.enableWindowManagement
        config.enableWindowManagement = false
        defer {
            config.enableWindowManagement = previousValue
            clearPendingWindowDragIntent()
        }

        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 220)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 220, topLeftY: 0, width: 200, height: 220)

        XCTAssertFalse(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: target.swapDropZoneRect.orDie().center,
            subject: .window,
            detachOrigin: .window,
        ))
    }

    @MainActor
    func testUnmanagedDetachedTabStillOffersTabReentryHint() {
        setUpWorkspacesForTests()
        clearPendingWindowDragIntent()
        let previousWindowManagement = config.enableWindowManagement
        let previousWindowTabs = config.windowTabs.enabled
        config.enableWindowManagement = false
        config.windowTabs.enabled = true
        defer {
            config.enableWindowManagement = previousWindowManagement
            config.windowTabs.enabled = previousWindowTabs
            clearPendingWindowDragIntent()
        }

        let workspace = Workspace.get(byName: "tabs")
        XCTAssertTrue(workspace.focusWorkspace())
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let source = TestWindow.new(id: 1, parent: tabGroup)
        let target = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)
        source.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)
        target.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 420, height: 246)

        XCTAssertTrue(updatePendingWindowDragIntent(
            sourceWindow: source,
            mouseLocation: tabGroup.windowTabDropInteractionRect.orDie().center,
            subject: .window,
            detachOrigin: .tabStrip,
        ))

        XCTAssertEqual(debugPendingWindowDragIntentSummary()?.kind, .tabStack(targetWindowId: target.windowId))
    }
}
