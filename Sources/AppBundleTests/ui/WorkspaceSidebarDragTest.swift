import AppKit
@testable import AppBundle
import XCTest

struct WorkspaceSidebarDragTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

private func makeWorkspaceSidebarSearchFixture() -> [WorkspaceSidebarWorkspaceViewModel] {
    let releaseNotes = WorkspaceSidebarWindowViewModel(
        windowId: 101,
        workspaceName: "coding",
        appName: "Xcode",
        appBundleId: "com.apple.dt.Xcode",
        appBundlePath: "/Applications/Xcode.app",
        title: "ReleaseNotes.swift",
        isFocused: false,
    )
    let terminal = WorkspaceSidebarWindowViewModel(
        windowId: 102,
        workspaceName: "coding",
        appName: "Terminal",
        appBundleId: "com.apple.Terminal",
        appBundlePath: "/System/Applications/Utilities/Terminal.app",
        title: "server",
        isFocused: false,
    )
    let browserTab = WorkspaceSidebarWindowViewModel(
        windowId: 202,
        workspaceName: "research",
        appName: "Safari",
        appBundleId: "com.apple.Safari",
        appBundlePath: "/Applications/Safari.app",
        title: "WindowServer docs",
        isFocused: false,
    )
    let notesTab = WorkspaceSidebarWindowViewModel(
        windowId: 203,
        workspaceName: "research",
        appName: "Notes",
        appBundleId: "com.apple.Notes",
        appBundlePath: "/System/Applications/Notes.app",
        title: "Ideas",
        isFocused: false,
    )
    let browserGroup = WorkspaceSidebarTabGroupViewModel(
        representativeWindowId: 201,
        workspaceName: "research",
        title: "Docs",
        windowCount: 2,
        isFocused: false,
        tabs: [browserTab, notesTab],
    )

    return [
        WorkspaceSidebarWorkspaceViewModel(
            name: "coding",
            projectId: workspaceProjectDefaultId,
            displayName: "Coding",
            sidebarLabel: "Coding",
            isGeneratedName: false,
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [
                WorkspaceSidebarItemViewModel(kind: .window(releaseNotes)),
                WorkspaceSidebarItemViewModel(kind: .window(terminal)),
            ],
        ),
        WorkspaceSidebarWorkspaceViewModel(
            name: "research",
            projectId: workspaceProjectDefaultId,
            displayName: "Research",
            sidebarLabel: "Research",
            isGeneratedName: false,
            monitorScopeId: workspaceSidebarDefaultScopeId,
            monitorName: nil,
            isFocused: false,
            isVisible: true,
            items: [WorkspaceSidebarItemViewModel(kind: .tabGroup(browserGroup))],
        ),
    ]
}

final class WorkspaceSidebarDragTest: XCTestCase {
    @MainActor
    func testWorkspaceSidebarSnapshotIncludesEmptyWorkspaceInBrowsedProject() async {
        setUpWorkspacesForTests()
        let project = createWorkspaceProject()
        let projectWorkspaceNames = Set(Workspace.all.filter { $0.projectId == project.id }.map(\.name))

        XCTAssertFalse(projectWorkspaceNames.isEmpty)
        XCTAssertFalse(projectWorkspaceNames.contains(focus.workspace.name))

        let sidebarWorkspaces = await buildWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus,
            workspaceLabels: [:],
            availableMonitors: sortedMonitors,
        )
        let sidebarProjectWorkspaceNames = Set(sidebarWorkspaces.filter { $0.projectId == project.id }.map(\.name))

        XCTAssertEqual(sidebarProjectWorkspaceNames, projectWorkspaceNames)
    }

    @MainActor
    func testWindowIntentPreviewRendersBelowWorkspaceSidebar() {
        XCTAssertLessThan(
            WindowDropIntentOverlayPanelController.shared.level.rawValue,
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

    @MainActor
    func testWorkspaceSidebarActionsExposeWindowAndTabGroupDragClosures() {
        var received: [String] = []
        let pointer = CGPoint(x: 12, y: 34)
        let actions = WorkspaceSidebarActions(
            windowDragChanged: { windowId, pointer in
                received.append("window-changed:\(windowId):\(pointer.x),\(pointer.y)")
            },
            windowDragEnded: { _, pointer in
                received.append("window-ended:\(pointer.x),\(pointer.y)")
            },
            tabGroupDragChanged: { windowId, pointer in
                received.append("group-changed:\(windowId):\(pointer.x),\(pointer.y)")
            },
            tabGroupDragEnded: { _, pointer in
                received.append("group-ended:\(pointer.x),\(pointer.y)")
            },
        )

        actions.windowDragChanged(101, pointer)
        actions.windowDragEnded(101, pointer)
        actions.tabGroupDragChanged(202, pointer)
        actions.tabGroupDragEnded(202, pointer)

        XCTAssertEqual(received, [
            "window-changed:101:12.0,34.0",
            "window-ended:12.0,34.0",
            "group-changed:202:12.0,34.0",
            "group-ended:12.0,34.0",
        ])
    }

    @MainActor
    func testWorkspaceSidebarFallbackWorkspaceNameFindsWindowsAndTabGroups() {
        let previousWorkspaces = TrayMenuModel.shared.workspaceSidebarWorkspaces
        defer { TrayMenuModel.shared.workspaceSidebarWorkspaces = previousWorkspaces }

        let window = WorkspaceSidebarWindowViewModel(
            windowId: 101,
            workspaceName: "coding",
            appName: "Editor",
            appBundleId: nil,
            appBundlePath: nil,
            title: "File.swift",
            isFocused: false,
        )
        let tab = WorkspaceSidebarWindowViewModel(
            windowId: 202,
            workspaceName: "research",
            appName: "Browser",
            appBundleId: nil,
            appBundlePath: nil,
            title: "Docs",
            isFocused: false,
        )
        let group = WorkspaceSidebarTabGroupViewModel(
            representativeWindowId: 201,
            workspaceName: "research",
            title: "Research",
            windowCount: 1,
            isFocused: false,
            tabs: [tab],
        )
        TrayMenuModel.shared.workspaceSidebarWorkspaces = [
            WorkspaceSidebarWorkspaceViewModel(
                name: "coding",
                projectId: workspaceProjectDefaultId,
                displayName: "Coding",
                sidebarLabel: "Coding",
                isGeneratedName: false,
                monitorScopeId: workspaceSidebarDefaultScopeId,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [WorkspaceSidebarItemViewModel(kind: .window(window))],
            ),
            WorkspaceSidebarWorkspaceViewModel(
                name: "research",
                projectId: workspaceProjectDefaultId,
                displayName: "Research",
                sidebarLabel: "Research",
                isGeneratedName: false,
                monitorScopeId: workspaceSidebarDefaultScopeId,
                monitorName: nil,
                isFocused: false,
                isVisible: true,
                items: [WorkspaceSidebarItemViewModel(kind: .tabGroup(group))],
            ),
        ]

        XCTAssertEqual(workspaceSidebarFallbackWorkspaceName(for: 101), "coding")
        XCTAssertEqual(workspaceSidebarFallbackWorkspaceName(for: 201), "research")
        XCTAssertEqual(workspaceSidebarFallbackWorkspaceName(for: 202), "research")
        XCTAssertNil(workspaceSidebarFallbackWorkspaceName(for: 999))
    }

    func testWorkspaceSidebarSearchFiltersByWindowTitleAndAppName() {
        let workspaces = makeWorkspaceSidebarSearchFixture()

        let titleResults = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: "release",
        )[workspaceProjectDefaultId] ?? []
        XCTAssertEqual(titleResults.map(\.name), ["coding"])
        XCTAssertEqual(titleResults.first?.items.map(\.id), ["window:101"])

        let appResults = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: "safari",
        )[workspaceProjectDefaultId] ?? []
        XCTAssertEqual(appResults.map(\.name), ["research"])
        XCTAssertEqual(appResults.first?.items.map(\.id), ["group:201"])
        if case .tabGroup(let group) = appResults.first?.items.first?.kind {
            XCTAssertEqual(group.tabs.map(\.windowId), [202, 203])
            XCTAssertEqual(group.searchVisibleTabs?.map(\.windowId), [202])
        } else {
            XCTFail("Expected tab group search result")
        }
        XCTAssertEqual(workspaceSidebarSearchSelections(workspaces: appResults), [.window(202)])
    }

    func testWorkspaceSidebarSearchKeepsWholeWorkspaceForWorkspaceMatch() {
        let workspaces = makeWorkspaceSidebarSearchFixture()

        let results = workspaceSidebarFilteredWorkspacesByProject(
            [workspaceProjectDefaultId: workspaces],
            projects: [],
            query: "coding",
        )[workspaceProjectDefaultId] ?? []

        XCTAssertEqual(results.map(\.name), ["coding"])
        XCTAssertEqual(results.first?.items.map(\.id), ["window:101", "window:102"])
    }

    func testWorkspaceSidebarInlineTextDeletesLastWord() {
        XCTAssertEqual("release notes".deletingLastWord(), "release ")
        XCTAssertEqual("release notes   ".deletingLastWord(), "release ")
        XCTAssertEqual("release".deletingLastWord(), "")
    }

    func testWorkspaceSidebarDragPayloadRoundTripsWindowAndTabGroupIds() {
        XCTAssertEqual(
            WorkspaceSidebarDragPayload(encodedValue: WorkspaceSidebarDragPayload.window(17).encodedValue),
            .window(17),
        )
        XCTAssertEqual(
            WorkspaceSidebarDragPayload(encodedValue: WorkspaceSidebarDragPayload.tabGroup(23).encodedValue),
            .tabGroup(23),
        )
        XCTAssertNil(WorkspaceSidebarDragPayload(encodedValue: "bogus:23"))
    }

    func testWorkspaceSidebarCreateScopeUsesFocusedScopeForSyntheticSelections() {
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: workspaceSidebarDefaultScopeId,
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:target")
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: workspaceSidebarFocusedScopeId,
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:a")
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: workspaceSidebarAllScopeId,
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:target")
        XCTAssertEqual(workspaceSidebarWorkspaceCreateScope(
            selectedScopeId: "monitor:b",
            targetMonitorScopeId: "monitor:target",
            focusedScopeId: "monitor:a"
        ), "monitor:b")
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

    func testSidebarSelectedProjectKeepsPreviousProject() {
        XCTAssertEqual(
            resolvedWorkspaceSidebarSelectedProjectId(
                validProjectIds: [workspaceProjectDefaultId, "project-1", "project-2"],
                previousSelectedProjectId: "project-1",
                previousActiveProjectId: workspaceProjectDefaultId,
                fallbackProjectId: "project-2",
            ),
            "project-1",
        )
    }

    func testSidebarSelectedProjectFollowsActualProjectWhenNotBrowsing() {
        XCTAssertEqual(
            resolvedWorkspaceSidebarSelectedProjectId(
                validProjectIds: [workspaceProjectDefaultId, "project-1", "project-2"],
                previousSelectedProjectId: "project-1",
                previousActiveProjectId: "project-1",
                fallbackProjectId: "project-2",
            ),
            "project-2",
        )
    }

    func testSidebarSelectedProjectFallsBackAfterDeletedProject() {
        XCTAssertEqual(
            resolvedWorkspaceSidebarSelectedProjectId(
                validProjectIds: [workspaceProjectDefaultId, "project-1"],
                previousSelectedProjectId: "project-2",
                previousActiveProjectId: workspaceProjectDefaultId,
                fallbackProjectId: "project-1",
            ),
            "project-1",
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

    func testWorkspaceSidebarDefaultScopeShowsWholeProject() {
        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspaceMonitorScopeId: "monitor:1440.0,0.0",
                selectedScopeId: workspaceSidebarDefaultScopeId,
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

    func testWorkspaceSidebarAllMonitorScopeShowsNonVisibleWorkspaces() {
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "2",
            projectId: workspaceProjectDefaultId,
            displayName: "2",
            sidebarLabel: "2",
            isGeneratedName: false,
            monitorScopeId: "monitor:1440.0,0.0",
            monitorName: "Secondary",
            isFocused: false,
            isVisible: false,
            items: [],
        )

        XCTAssertTrue(
            workspaceSidebarWorkspaceMatchesScope(
                workspace,
                selectedScopeId: workspaceSidebarAllScopeId,
                focusedMonitorScopeId: "monitor:0.0,0.0",
            )
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

    func testWorkspaceSidebarInUseOverlayOnlyAppliesToVisibleOtherMonitor() {
        let workspace = WorkspaceSidebarWorkspaceViewModel(
            name: "2",
            projectId: workspaceProjectDefaultId,
            displayName: "2",
            sidebarLabel: "2",
            isGeneratedName: false,
            monitorScopeId: "monitor:1440.0,0.0",
            monitorName: "Side Display",
            isFocused: false,
            isVisible: true,
            items: [],
        )
        XCTAssertTrue(
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                workspace,
                selectedScopeId: "monitor:0.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                workspace,
                selectedScopeId: "monitor:1440.0,0.0",
            ),
        )
        XCTAssertFalse(
            workspaceSidebarWorkspaceIsInUseOnOtherDisplay(
                workspace,
                selectedScopeId: workspaceSidebarAllScopeId,
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

}
