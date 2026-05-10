import AppKit
@testable import AppBundle
import XCTest

private struct WorkspaceSidebarDragTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

final class WorkspaceSidebarDragTest: XCTestCase {
    @MainActor
    func testWindowIntentPreviewRendersBelowWorkspaceSidebar() {
        XCTAssertLessThan(
            WindowTabDropPreviewPanel.shared.level.rawValue,
            WorkspaceSidebarPanel.shared.level.rawValue,
        )
    }

    @MainActor
    func testWindowChromeUsesNormalAppWindowLayer() {
        XCTAssertEqual(
            WinMuxPanelLayer.windowChrome.level.rawValue,
            NSWindow.Level.normal.rawValue,
        )
        XCTAssertLessThan(
            WinMuxPanelLayer.windowChrome.level.rawValue,
            WinMuxPanelLayer.windowIntentPreview.level.rawValue,
        )
    }

    @MainActor
    func testWorkspaceSidebarLayerIsAboveAllWinMuxPanels() {
        for layer in WinMuxPanelLayer.allCases where layer != .workspaceSidebar {
            XCTAssertLessThan(
                layer.level.rawValue,
                WinMuxPanelLayer.workspaceSidebar.level.rawValue,
                "\(layer) should render below the workspace sidebar",
            )
        }
    }

    func testLeftMouseButtonPressedUsesBitmask() {
        XCTAssertTrue(isLeftMouseButtonPressed(mask: 0b1))
        XCTAssertTrue(isLeftMouseButtonPressed(mask: 0b11))
        XCTAssertFalse(isLeftMouseButtonPressed(mask: 0b10))
        XCTAssertFalse(isLeftMouseButtonPressed(mask: 0))
    }

    func testWorkspaceSidebarDragInProgressRecognizesSidebarMoveSession() {
        XCTAssertTrue(isWorkspaceSidebarDragInProgress(kind: .move, startedInSidebar: true))
    }

    func testWorkspaceSidebarDragInProgressIgnoresNonSidebarMoves() {
        XCTAssertFalse(isWorkspaceSidebarDragInProgress(kind: .move, startedInSidebar: false))
        XCTAssertFalse(isWorkspaceSidebarDragInProgress(kind: .none, startedInSidebar: true))
    }

    func testWorkspaceSidebarActivationRequiresNoEditAndNoDrag() {
        XCTAssertTrue(shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: false))
        XCTAssertFalse(shouldHandleWorkspaceSidebarActivation(isEditing: true, isSidebarDragInProgress: false))
        XCTAssertFalse(shouldHandleWorkspaceSidebarActivation(isEditing: false, isSidebarDragInProgress: true))
    }

    func testWorkspaceSidebarActivationBlocksWhileAnyWorkspaceIsEditing() {
        XCTAssertFalse(
            shouldHandleWorkspaceSidebarActivation(
                editingWorkspaceName: "a",
                isSidebarDragInProgress: false,
            ),
        )
        XCTAssertTrue(
            shouldHandleWorkspaceSidebarActivation(
                editingWorkspaceName: nil,
                isSidebarDragInProgress: false,
            ),
        )
    }

    func testProjectSwipeDirectionRequiresHorizontalIntent() {
        XCTAssertEqual(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: -40, verticalTranslation: 4),
            1,
        )
        XCTAssertEqual(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: 40, verticalTranslation: 4),
            -1,
        )
        XCTAssertNil(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: -40, verticalTranslation: 38),
        )
        XCTAssertNil(
            workspaceSidebarProjectSwipeDirection(horizontalTranslation: -4, verticalTranslation: 0),
        )
    }

    func testProjectSwipeNavigatesWithoutWrapping() {
        XCTAssertEqual(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 1, projectCount: 3, direction: 1),
            2,
        )
        XCTAssertEqual(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 1, projectCount: 3, direction: -1),
            0,
        )
        XCTAssertNil(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 2, projectCount: 3, direction: 1),
        )
        XCTAssertNil(
            workspaceSidebarProjectIndexAfterSwipe(currentIndex: 0, projectCount: 3, direction: -1),
        )
    }

    func testProjectSwipeCreatesOnlyPastEdgesAfterBreakPoint() {
        XCTAssertFalse(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 1,
                projectCount: 3,
                direction: 1,
                distance: 120,
            ),
        )
        XCTAssertFalse(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 96,
            ),
        )
        XCTAssertTrue(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 110,
            ),
        )
        XCTAssertTrue(
            shouldCreateWorkspaceSidebarProjectAfterSwipe(
                currentIndex: 0,
                projectCount: 3,
                direction: -1,
                distance: 110,
            ),
        )
    }

    func testProjectSwipeFormationProgressOnlyAtEdges() {
        XCTAssertEqual(
            workspaceSidebarProjectEdgeCreationProgress(
                currentIndex: 1,
                projectCount: 3,
                direction: 1,
                distance: 100,
            ),
            0,
        )
        XCTAssertEqual(
            workspaceSidebarProjectEdgeCreationProgress(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 22,
            ),
            0,
        )
        XCTAssertEqual(
            workspaceSidebarProjectEdgeCreationProgress(
                currentIndex: 2,
                projectCount: 3,
                direction: 1,
                distance: 104,
            ),
            1,
        )
    }

    func testProjectSwipeSwitchProgressReachesOneAtNavigationThreshold() {
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 0), 0)
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 22), 0.5)
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 44), 1)
        XCTAssertEqual(workspaceSidebarProjectSwipeSwitchProgress(distance: 64), 1)
    }

    func testProjectPagerDragTracksRealAdjacentPagesDirectly() {
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: -60,
                currentIndex: 0,
                projectCount: 2,
                pageWidth: 200,
            ),
            -60,
        )
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: -240,
                currentIndex: 0,
                projectCount: 2,
                pageWidth: 200,
            ),
            -200,
        )
    }

    func testProjectPagerDragUsesResistanceAtProjectEdges() {
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: 120,
                currentIndex: 0,
                projectCount: 1,
                pageWidth: 200,
            ),
            52,
        )
        XCTAssertEqual(
            workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: -120,
                currentIndex: 0,
                projectCount: 1,
                pageWidth: 200,
            ),
            -52,
        )
    }

    func testProjectHueIsStableAndNormalized() {
        let firstHue = workspaceSidebarProjectHue(projectId: "project-alpha")
        let secondHue = workspaceSidebarProjectHue(projectId: "project-alpha")

        XCTAssertEqual(firstHue, secondHue)
        XCTAssertGreaterThanOrEqual(firstHue, 0)
        XCTAssertLessThan(firstHue, 1)
    }

    func testProjectColorHexNormalizes() {
        XCTAssertEqual(normalizedWorkspaceSidebarColorHex("#60a5fa"), "#60A5FA")
        XCTAssertEqual(normalizedWorkspaceSidebarColorHex("f87171"), "#F87171")
        XCTAssertNil(normalizedWorkspaceSidebarColorHex("#12345"))
        XCTAssertNil(normalizedWorkspaceSidebarColorHex("tomato"))
    }

    func testProjectColorUsesConfiguredHexWhenPresent() {
        XCTAssertNotNil(workspaceSidebarColor(hex: "#60A5FA"))
        XCTAssertNil(workspaceSidebarColor(hex: "not-a-color"))
    }

    func testProjectSwipeScrollDeltaUsesDragDirection() {
        XCTAssertEqual(
            workspaceSidebarProjectSwipeTranslationAfterScroll(currentTranslation: 0, scrollingDeltaX: 24),
            -24,
        )
        XCTAssertEqual(
            workspaceSidebarProjectSwipeTranslationAfterScroll(currentTranslation: -24, scrollingDeltaX: -10),
            -14,
        )
    }

    func testSidebarSelectedProjectFollowsActiveProject() {
        XCTAssertEqual(
            resolvedWorkspaceSidebarSelectedProjectId(
                validProjectIds: [workspaceProjectDefaultId, "project-1", "project-2"],
                activeProjectId: "project-2",
            ),
            "project-2",
        )
    }

    func testSidebarSelectedProjectFallsBackAfterDeletedProject() {
        XCTAssertEqual(
            resolvedWorkspaceSidebarSelectedProjectId(
                validProjectIds: [workspaceProjectDefaultId, "project-1"],
                activeProjectId: "project-2",
            ),
            workspaceProjectDefaultId,
        )
    }

    func testWorkspaceSidebarFocusedMonitorScopeOnlyMatchesFocusedMonitor() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:0.0,0.0",
                selectedScopeId: workspaceSidebarFocusedScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: workspaceSidebarFocusedScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarAllMonitorScopeMatchesAnyMonitor() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: workspaceSidebarAllScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarExplicitMonitorScopeOnlyMatchesThatMonitor() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: "monitor:1440.0,0.0",
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:0.0,0.0",
                selectedScopeId: "monitor:1440.0,0.0",
                focusedMonitorScopeId: "monitor:0.0,0.0",
            ),
        )
    }

    func testWorkspaceSidebarHoverCueWidthStaysCollapsed() {
        XCTAssertEqual(
            workspaceSidebarHoverCueWidth(collapsedWidth: 28, expandedWidth: 160),
            CGFloat(28),
        )
    }

    func testWorkspaceSidebarHoverCueWidthDoesNotProtrudeTowardExpandedWidth() {
        XCTAssertEqual(
            workspaceSidebarHoverCueWidth(collapsedWidth: 28, expandedWidth: 34),
            CGFloat(28),
        )
    }

    func testWorkspaceSidebarStatusBottomPaddingMatchesLeadingEdgePadding() {
        XCTAssertEqual(
            workspaceSidebarStatusBottomPadding(isCompact: true),
            workspaceSidebarOuterLeadingPadding(isCompact: true),
        )
        XCTAssertEqual(
            workspaceSidebarStatusBottomPadding(isCompact: false),
            workspaceSidebarOuterLeadingPadding(isCompact: false),
        )
    }

    func testWorkspaceSidebarHoverExpansionRequiresAtLeastThreeQuarterDepth() {
        XCTAssertFalse(
            isWorkspaceSidebarHoverDeepEnoughToExpand(
                mouseX: 8,
                sidebarMinX: 0,
                collapsedWidth: 28,
            ),
        )
        XCTAssertTrue(
            isWorkspaceSidebarHoverDeepEnoughToExpand(
                mouseX: 7,
                sidebarMinX: 0,
                collapsedWidth: 28,
            ),
        )
        XCTAssertTrue(
            isWorkspaceSidebarHoverDeepEnoughToExpand(
                mouseX: 14,
                sidebarMinX: 8,
                collapsedWidth: 28,
            ),
        )
    }

    func testMouseWindowDragInProgressRequiresMoveSessionWindowAndPressedButton() {
        XCTAssertTrue(isMouseWindowDragInProgress(kind: .move, draggedWindowId: 7, isLeftMouseButtonDown: true))
        XCTAssertFalse(isMouseWindowDragInProgress(kind: .none, draggedWindowId: 7, isLeftMouseButtonDown: true))
        XCTAssertFalse(isMouseWindowDragInProgress(kind: .move, draggedWindowId: nil, isLeftMouseButtonDown: true))
        XCTAssertFalse(isMouseWindowDragInProgress(kind: .move, draggedWindowId: 7, isLeftMouseButtonDown: false))
    }

    func testWorkspaceSidebarExpansionDelayOnlyAppliesToPassiveCollapsedHover() {
        XCTAssertTrue(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: false,
                isExpansionLocked: false,
                isMouseWindowDragInProgress: false,
            ),
        )
        XCTAssertFalse(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: true,
                isExpansionLocked: false,
                isMouseWindowDragInProgress: false,
            ),
        )
        XCTAssertFalse(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: false,
                isExpansionLocked: true,
                isMouseWindowDragInProgress: false,
            ),
        )
        XCTAssertFalse(
            shouldDelayWorkspaceSidebarExpansion(
                isExpanded: false,
                isExpansionLocked: false,
                isMouseWindowDragInProgress: true,
            ),
        )
    }

    func testWorkspaceHoverExitDoesNotClearNewerHoveredWorkspace() {
        XCTAssertEqual(
            nextWorkspaceSidebarHoveredWorkspaceName(
                currentHoveredWorkspaceName: "b",
                workspaceName: "a",
                isHovering: false,
            ),
            "b",
        )
    }

    func testWorkspaceHoverExitClearsMatchingHoveredWorkspace() {
        XCTAssertNil(
            nextWorkspaceSidebarHoveredWorkspaceName(
                currentHoveredWorkspaceName: "a",
                workspaceName: "a",
                isHovering: false,
            ),
        )
    }

    func testWindowHoverExitDoesNotClearNewerHoveredWindow() {
        XCTAssertEqual(
            nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: 2,
                windowId: 1,
                isHovering: false,
            ),
            2,
        )
    }

    func testWindowHoverExitClearsMatchingHoveredWindow() {
        XCTAssertNil(
            nextWorkspaceSidebarHoveredWindowId(
                currentHoveredWindowId: 1,
                windowId: 1,
                isHovering: false,
            ),
        )
    }

    func testSameWorkspaceSidebarDropTargetIsNotActionable() {
        XCTAssertFalse(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .workspace("1"),
            ),
        )
    }

    func testDifferentWorkspaceSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .workspace("2"),
            ),
        )
    }

    func testNewWorkspaceSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .newWorkspace,
            ),
        )
    }

    func testBlankSidebarAreaIsNotActionable() {
        XCTAssertFalse(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: nil,
            ),
        )
    }

    func testMonitorSidebarDropTargetIsActionable() {
        XCTAssertTrue(
            isActionableSidebarWorkspaceDropTarget(
                sourceWorkspaceName: "1",
                targetKind: .monitor("monitor:1920.0,0.0"),
            ),
        )
    }

    @MainActor
    func testSidebarNewWorkspaceTargetUsesDropPointMonitorBeforeSourceMonitor() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let target = workspaceSidebarTargetMonitor(
            selectedMonitor: nil,
            fallbackPoint: CGPoint(x: 2000, y: 20),
            fallbackWindowMonitor: main,
            focusedMonitor: main,
        )

        XCTAssertEqual(target.rect.topLeftCorner, secondary.rect.topLeftCorner)
    }

    @MainActor
    func testSidebarNewWorkspaceTargetHonorsExplicitMonitorSelection() {
        let main = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        defer { setMonitorsForTests(nil) }

        let target = workspaceSidebarTargetMonitor(
            selectedMonitor: main,
            fallbackPoint: CGPoint(x: 2000, y: 20),
            fallbackWindowMonitor: secondary,
            focusedMonitor: secondary,
        )

        XCTAssertEqual(target.rect.topLeftCorner, main.rect.topLeftCorner)
    }

    @MainActor
    func testSecondaryMonitorWindowsAreManaged() {
        XCTAssertTrue(shouldWinMuxManageWindow(at: CGPoint(x: 2000, y: 20)))
    }

    @MainActor
    func testMonitorScopeResolvesMonitorPoint() {
        let secondary = WorkspaceSidebarDragTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([secondary])
        defer { setMonitorsForTests(nil) }

        let scopeId = workspaceSidebarMonitorScopeId(for: secondary)

        XCTAssertEqual(workspaceSidebarMonitorScopePoint(scopeId), secondary.rect.topLeftCorner)
        XCTAssertEqual(workspaceSidebarMonitor(forScopeId: scopeId)?.rect.topLeftCorner, secondary.rect.topLeftCorner)
    }

    func testVisibleWorkspacesAreGroupedByProjectAndScope() {
        let focusedScope = "monitor:0.0"
        let otherScope = "monitor:1920.0"
        let workspaces = [
            WorkspaceSidebarWorkspaceViewModel(
                name: "1",
                projectId: "default",
                displayName: "1",
                sidebarLabel: "",
                isGeneratedName: false,
                monitorScopeId: focusedScope,
                monitorName: nil,
                isFocused: true,
                isVisible: true,
                items: [],
            ),
            WorkspaceSidebarWorkspaceViewModel(
                name: "2",
                projectId: "project-b",
                displayName: "2",
                sidebarLabel: "",
                isGeneratedName: false,
                monitorScopeId: otherScope,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [],
            ),
        ]

        let grouped = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: workspaces,
            selectedScopeId: workspaceSidebarFocusedScopeId,
            focusedMonitorScopeId: focusedScope,
        )

        XCTAssertEqual(grouped["default"]?.map(\.name), ["1"])
        XCTAssertNil(grouped["project-b"])
    }

    func testProjectPagerRendersOnlyCurrentAndSwipeTargetPages() {
        XCTAssertTrue(shouldRenderWorkspaceSidebarProjectPage(index: 1, displayIndex: 1, swipeDirection: nil, projectCount: 4))
        XCTAssertFalse(shouldRenderWorkspaceSidebarProjectPage(index: 0, displayIndex: 1, swipeDirection: nil, projectCount: 4))
        XCTAssertTrue(shouldRenderWorkspaceSidebarProjectPage(index: 2, displayIndex: 1, swipeDirection: 1, projectCount: 4))
        XCTAssertFalse(shouldRenderWorkspaceSidebarProjectPage(index: 3, displayIndex: 1, swipeDirection: 1, projectCount: 4))
    }
}
