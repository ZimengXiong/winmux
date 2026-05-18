@testable import AppBundle
import AppKit
import CoreGraphics
import XCTest

struct WindowTabsTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

func cgWindowBounds(windowNumber: Int) -> CGRect? {
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionIncludingWindow],
        CGWindowID(windowNumber),
    ) as? [[String: Any]],
        let bounds = windows.first?[kCGWindowBounds as String] as? [String: Any],
        let x = bounds["X"] as? NSNumber,
        let y = bounds["Y"] as? NSNumber,
        let width = bounds["Width"] as? NSNumber,
        let height = bounds["Height"] as? NSNumber
    else {
        return nil
    }
    return CGRect(
        x: CGFloat(truncating: x),
        y: CGFloat(truncating: y),
        width: CGFloat(truncating: width),
        height: CGFloat(truncating: height),
    )
}

final class WindowTabsTest: XCTestCase {
    @MainActor
    func testCreateTabStackFromTwoSiblingWindows() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let source = TestWindow.new(id: 1, parent: root)
        let target = TestWindow.new(id: 2, parent: root)

        createOrAppendWindowTabStack(sourceWindow: source, onto: target)

        assertEquals(root.layoutDescription, .h_tiles([.v_tab_group([.window(2), .window(1)])]))
    }

    @MainActor
    func testAppendWindowToExistingTabStack() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        root.layout = .tabGroup
        let target = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)
        let source = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        createOrAppendWindowTabStack(sourceWindow: source, onto: target)

        assertEquals(root.layoutDescription, .h_tab_group([.window(2), .window(1), .window(3)]))
    }

    @MainActor
    func testRemoveWindowFromNestedTabStack() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let leading = TestWindow.new(id: 0, parent: root)
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
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
    func testRemoveWindowFromNestedTwoTabStackFlattensDeadTabGroup() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let stack = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
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
        root.layout = .tabGroup
        let removed = TestWindow.new(id: 1, parent: root)
        let expectedActive = TestWindow.new(id: 2, parent: root)
        _ = TestWindow.new(id: 3, parent: root)
        expectedActive.markAsMostRecentChild()

        XCTAssertTrue(removeWindowFromTabStack(removed))

        let rebuiltTabGroup = root.children.first as? TilingContainer
        XCTAssertNotNil(rebuiltTabGroup)
        XCTAssertEqual(rebuiltTabGroup?.layout, .tabGroup)
        XCTAssertEqual(rebuiltTabGroup?.tabActiveWindow, expectedActive)
    }

    @MainActor
    func testFocusAfterWindowClosurePrefersPreviousActiveTabOverMacOsFallback() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        _ = TestWindow.new(id: 3, parent: tabGroup)
        let expectedTab = TestWindow.new(id: 4, parent: tabGroup)
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
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        _ = TestWindow.new(id: 3, parent: tabGroup)
        let expectedTab = TestWindow.new(id: 4, parent: tabGroup)
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
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        _ = TestWindow.new(id: 3, parent: tabGroup)
        let expectedTab = TestWindow.new(id: 4, parent: tabGroup)
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
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let firstTab = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        _ = TestWindow.new(id: 3, parent: tabGroup)
        let expectedTab = TestWindow.new(id: 4, parent: tabGroup)
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
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let staleFallbackTab = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        let expectedTab = TestWindow.new(id: 3, parent: tabGroup)
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

    @MainActor
    func testFocusAfterWindowClosurePrefersSnapshotPreviousPreviousFocusOverFallbackTabWhenClosingTransientWindow() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let staleFallbackTab = TestWindow.new(id: 1, parent: tabGroup)
        let expectedTab = TestWindow.new(id: 2, parent: tabGroup)
        let closingWindow = TestWindow.new(id: 9, parent: workspace)

        let replacementFocus = focusAfterWindowClosure(
            closingWindow: closingWindow,
            deadWindowWorkspace: workspace,
            currentFocus: staleFallbackTab.toLiveFocusOrNil().orDie(),
            previousFocus: nil,
            previousPreviousFocus: nil,
            refreshSnapshotCloseFallback: staleFallbackTab.toLiveFocusOrNil(),
            refreshSnapshotPreviousFocus: closingWindow.toLiveFocusOrNil(),
            refreshSnapshotPreviousPreviousFocus: expectedTab.toLiveFocusOrNil(),
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
    func testTabGroupDropAndSwapZonesDoNotOverlap() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let root = workspace.rootTilingContainer
        let tabGroup = TilingContainer(parent: root, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let active = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 260)
        active.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 34, width: 400, height: 226)
        active.markAsMostRecentChild()

        let tabBarRect = tabGroup.windowTabBarRect.orDie()
        let groupFrameRect = tabGroup.windowTabGroupFrameRect.orDie()
        let tabDropZone = tabGroup.windowTabDropZoneRect.orDie()
        let tabInteractionZone = tabGroup.windowTabDropInteractionRect.orDie()
        let swapDropZone = tabGroup.swapDropZoneRect.orDie()
        let tabGroupFrame = tabGroup.lastAppliedLayoutPhysicalRect.orDie()

        XCTAssertEqual(groupFrameRect.topLeftX, tabGroupFrame.topLeftX)
        XCTAssertEqual(groupFrameRect.topLeftY, tabGroupFrame.topLeftY)
        XCTAssertEqual(groupFrameRect.width, tabGroupFrame.width)
        XCTAssertEqual(groupFrameRect.height, tabGroupFrame.height)
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
    func testTabGroupSwapZoneKeepsBodyActive() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 1, parent: tabGroup)
        _ = TestWindow.new(id: 2, parent: tabGroup)
        tabGroup.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 420, height: 280)

        let swapDropZone = tabGroup.swapDropZoneRect.orDie()
        XCTAssertTrue(swapDropZone.contains(swapDropZone.center))
    }

    @MainActor
    func testUnmanagedLayoutKeepsVisibleWindowFrame() async throws {
        setUpWorkspacesForTests()
        config.enableWindowManagement = false
        let workspace = Workspace.get(byName: "tabs")
        let window = TestWindow.new(
            id: 1,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 50, topLeftY: 70, width: 320, height: 240),
        )

        try await workspace.layoutWorkspace()

        let rect = try await window.getAxRect().orDie()
        XCTAssertEqual(rect.topLeftX, 50)
        XCTAssertEqual(rect.topLeftY, 70)
        XCTAssertEqual(rect.width, 320)
        XCTAssertEqual(rect.height, 240)
    }
}
