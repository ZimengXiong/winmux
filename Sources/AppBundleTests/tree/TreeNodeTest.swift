@testable import AppBundle
import XCTest

@MainActor
final class TreeNodeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testChildParentCyclicReferenceMemoryLeak() {
        let workspace = Workspace.get(byName: name) // Don't cache root node
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        XCTAssertTrue(window.parent != nil)
        workspace.rootTilingContainer.unbindFromParent()
        XCTAssertTrue(window.parent == nil)
    }

    func testIsEffectivelyEmpty() {
        let workspace = Workspace.get(byName: name)

        XCTAssertTrue(workspace.isEffectivelyEmpty)
        weak let window: TestWindow? = .new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertNotEqual(window, nil)
        XCTAssertTrue(!workspace.isEffectivelyEmpty)
        window!.unbindFromParent()
        XCTAssertTrue(workspace.isEffectivelyEmpty)

        // Don't save to local variable
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        XCTAssertTrue(!workspace.isEffectivelyEmpty)
    }

    func testNormalizeContainers_dontRemoveRoot() {
        let workspace = Workspace.get(byName: name)
        weak let root = workspace.rootTilingContainer
        func test() {
            XCTAssertNotEqual(root, nil)
            XCTAssertTrue(root!.isEffectivelyEmpty)
            workspace.normalizeContainers()
            XCTAssertNotEqual(root, nil)
        }
        test()

        config.enableNormalizationFlattenContainers = true
        test()
    }

    func testNormalizeContainers_singleWindowChild() {
        config.enableNormalizationFlattenContainers = true
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
            }
        }
        workspace.normalizeContainers()
        assertEquals(
            .h_tiles([.window(0), .window(1)]),
            workspace.rootTilingContainer.layoutDescription,
        )
    }

    func testNormalizeContainers_removeEffectivelyEmpty() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                _ = TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1)
            }
        }
        assertEquals(workspace.rootTilingContainer.children.count, 1)
        workspace.normalizeContainers()
        assertEquals(workspace.rootTilingContainer.children.count, 0)
    }

    func testNormalizeContainers_flattenContainers() {
        let workspace = Workspace.get(byName: name) // Don't cache root node
        workspace.rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
            }
        }
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children.singleOrNil() is TilingContainer)

        config.enableNormalizationFlattenContainers = true
        workspace.normalizeContainers()
        XCTAssertTrue(workspace.rootTilingContainer.children.singleOrNil() is TestWindow)
    }

    func testReconcileWorkspaceStateKeepsOnlyEmptyWorkspaceInProject() {
        let project = createWorkspaceProject()
        let workspace = Workspace.get(byName: "draft")
        workspace.markAsSidebarManaged()
        workspace.assignProject(project.id)

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.all.contains(workspace))
    }

    func testReconcileWorkspaceStateKeepsPersistentEmptyWorkspace() {
        config.persistentWorkspaces = ["keep"]
        let workspace = Workspace.get(byName: "keep")

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.all.contains(workspace))
    }

    func testReconcileWorkspaceStateKeepsFreshFocusedEmptyWorkspace() {
        let workspace = Workspace.get(byName: "draft")
        workspace.markAsSidebarManaged()
        _ = workspace.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.all.contains(workspace))
        XCTAssertEqual(focus.workspace, workspace)
    }

    func testReconcileWorkspaceStateKeepsFocusedEmptyWorkspaceWhenNotFresh() {
        let workspace = Workspace.get(byName: "empty")
        _ = workspace.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.existing(byName: workspace.name) === workspace)
        XCTAssertEqual(focus.workspace.name, workspace.name)
        XCTAssertTrue(isUserFacingWorkspace(focus.workspace, focusedWorkspace: focus.workspace))
    }

    func testReconcileWorkspaceStateDeletesUnfocusedEmptyWorkspaceAfterLeavingIt() {
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 101, parent: occupiedWorkspace.rootTilingContainer)
        let draftWorkspace = Workspace.get(byName: "draft")
        draftWorkspace.markAsSidebarManaged()
        _ = draftWorkspace.focusWorkspace()
        _ = occupiedWorkspace.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: draftWorkspace.name))
        XCTAssertEqual(
            userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).filter(\.isOrdinaryEmptySlot),
            [],
        )
    }

    func testReconcileWorkspaceStateDeletesWorkspaceWithOnlyDetachedMinimizedWindow() {
        let workspace = Workspace.get(byName: "collected")
        let window = TestWindow.new(id: 111, parent: workspace.rootTilingContainer)
        let otherWorkspace = Workspace.get(byName: "other")

        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = otherWorkspace.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(window.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: nil))
        XCTAssertNil(Workspace.existing(byName: workspace.name))
    }

    func testReconcileWorkspaceStateKeepsFocusedSidebarWorkspaceAfterLastWindowCloses() {
        let workspace = Workspace.get(byName: "2")
        workspace.markAsSidebarManaged()
        _ = workspace.focusWorkspace()
        let window = TestWindow.new(id: 113, parent: workspace.rootTilingContainer)

        window.unbindFromParent()
        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.existing(byName: workspace.name) === workspace)
    }

    func testReconcileWorkspaceStateKeepsFocusedSidebarWorkspaceAfterLastWindowMinimizes() {
        let survivingWorkspace = Workspace.get(byName: "1")
        survivingWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 115, parent: survivingWorkspace.rootTilingContainer)
        let workspace = Workspace.get(byName: "2")
        workspace.markAsSidebarManaged()
        _ = workspace.focusWorkspace()
        let window = TestWindow.new(id: 114, parent: workspace.rootTilingContainer)

        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.existing(byName: workspace.name) === workspace)
        XCTAssertNotEqual(nextSidebarCreatedWorkspaceName(), workspace.name)
    }

    func testRestoredMinimizedWindowUsesCurrentWorkspaceWhenOriginalWorkspaceWasCollected() async throws {
        let workspace = Workspace.get(byName: "collected")
        let window = TestWindow.new(id: 112, parent: workspace.rootTilingContainer)
        let otherWorkspace = Workspace.get(byName: "other")

        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = otherWorkspace.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        window.nativeIsMacosMinimized = false

        try await exitMacOsNativeUnconventionalState(
            window: window,
            prevParentKind: .tilingContainer,
            prevWorkspaceName: workspace.name,
            workspace: otherWorkspace,
        )

        XCTAssertNil(Workspace.existing(byName: workspace.name))
        XCTAssertEqual(window.nodeWorkspace, otherWorkspace)
    }

    func testRememberMacOsLayoutOriginCanDetachFromWorkspace() {
        let workspace = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)

        XCTAssertEqual(
            window.layoutReason,
            .macos(prevParentKind: .tilingContainer, prevWorkspaceName: nil),
        )
    }

    func testRememberMacOsLayoutOriginCapturesCurrentWorkspace() {
        let workspace = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        window.rememberMacOsLayoutOrigin()

        XCTAssertEqual(
            window.layoutReason,
            .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name),
        )
    }

    func testNextSidebarDraftWorkspaceNameReusesLowestAvailableGap() {
        _ = Workspace.get(byName: "__sidebar_draft_workspace_1")
        _ = Workspace.get(byName: "__sidebar_draft_workspace_3")

        XCTAssertEqual(nextSidebarDraftWorkspaceName(), "__sidebar_draft_workspace_2")
    }

    func testNextSidebarDraftWorkspaceNameReusesCollectedDraftName() {
        _ = Workspace.get(byName: "__sidebar_draft_workspace_1")
        _ = Workspace.get(byName: "__sidebar_draft_workspace_2")

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(nextSidebarDraftWorkspaceName(), "__sidebar_draft_workspace_1")
    }

    func testNextSidebarDraftWorkspaceNameClearsStalePersistedDraftLabelBeforeReuse() {
        config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"] = "Old Name"

        XCTAssertEqual(nextSidebarDraftWorkspaceName(), "__sidebar_draft_workspace_1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"])
    }

    func testReconcileWorkspaceStateClearsCollectedDraftWorkspaceLabel() {
        config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"] = "Old Name"
        _ = Workspace.get(byName: "__sidebar_draft_workspace_1")

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"])
        XCTAssertEqual(workspaceDisplayName("__sidebar_draft_workspace_1"), "Workspace 1")
    }

    func testReconcileWorkspaceStateClearsCollectedWorkspaceLabel() {
        config.workspaceSidebar.workspaceLabels["ghost"] = "Ghost Name"
        _ = Workspace.get(byName: "ghost")

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(config.workspaceSidebar.workspaceLabels["ghost"])
        XCTAssertEqual(workspaceDisplayName("ghost"), "ghost")
    }

    func testReconcileWorkspaceStateClearsOrphanedDraftWorkspaceLabel() {
        config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_7"] = "Old Name"

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_7"])
        XCTAssertEqual(workspaceDisplayName("__sidebar_draft_workspace_7"), "Workspace 7")
    }

    func testWorkspaceDisplayNameUsesSidebarDraftFallback() {
        XCTAssertEqual(workspaceDisplayName("__sidebar_draft_workspace_4"), "Workspace 4")
    }

    func testShouldShowWorkspaceInSidebarIncludesPersistentEmptyWorkspace() {
        config.persistentWorkspaces = ["persistent"]
        let persistentWorkspace = Workspace.get(byName: "persistent")

        XCTAssertTrue(
            shouldShowWorkspaceInSidebar(
                persistentWorkspace,
                currentFocus: focus,
                isEditingWorkspace: false,
            ),
        )
    }

    func testUserFacingWorkspacesExcludeUnretainedFocusedEmptyWorkspace() {
        let focusedWorkspace = Workspace.get(byName: "focused")
        let hiddenEmptyWorkspace = Workspace.get(byName: "hidden-empty")
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 2, parent: occupiedWorkspace.rootTilingContainer)

        let result = userFacingWorkspaces(
            [focusedWorkspace, hiddenEmptyWorkspace, occupiedWorkspace],
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertEqual(result, [occupiedWorkspace])
    }

    func testUserFacingWorkspacesExcludeUnretainedSidebarManagedEmptyWorkspace() {
        let focusedWorkspace = Workspace.get(byName: "focused")
        focusedWorkspace.markAsSidebarManaged()
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 202, parent: occupiedWorkspace.rootTilingContainer)

        let result = userFacingWorkspaces(
            [focusedWorkspace, occupiedWorkspace],
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertEqual(result, [occupiedWorkspace])
    }

    func testUserFacingWorkspacesIncludePersistentEmptyWorkspace() {
        config.persistentWorkspaces = ["persistent"]
        let persistentWorkspace = Workspace.get(byName: "persistent")
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 203, parent: occupiedWorkspace.rootTilingContainer)

        let result = userFacingWorkspaces(
            [persistentWorkspace, occupiedWorkspace],
            focusedWorkspace: focus.workspace,
        )

        XCTAssertEqual(result, [persistentWorkspace, occupiedWorkspace])
    }

    func testFocusedEmptyWorkspaceRemainsNativeAfterMaintenance() {
        let emptyWorkspace = Workspace.get(byName: "empty")
        _ = emptyWorkspace.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.existing(byName: emptyWorkspace.name) === emptyWorkspace)
        XCTAssertEqual(emptyWorkspace.workspaceMonitor.activeWorkspace, emptyWorkspace)
    }

    func testTransientBlankWorkspaceKeepsStableIdentityWhileEmpty() {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsTransientBlank()
        _ = workspace.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(Workspace.existing(byName: "1") === workspace)
        XCTAssertEqual(focus.workspace, workspace)
    }

    func testUserFacingWorkspacesExcludeWorkspaceWithOnlyMacosFullscreenWindows() {
        let focusedWorkspace = Workspace.get(byName: "focused")
        let fullscreenOnlyWorkspace = Workspace.get(byName: "fullscreen-only")
        _ = TestWindow.new(id: 22, parent: fullscreenOnlyWorkspace.macOsNativeFullscreenWindowsContainer)
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 23, parent: occupiedWorkspace.rootTilingContainer)

        let result = userFacingWorkspaces(
            [focusedWorkspace, fullscreenOnlyWorkspace, occupiedWorkspace],
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertEqual(result, [occupiedWorkspace])
        XCTAssertFalse(workspaceHasSidebarVisibleWindows(fullscreenOnlyWorkspace))
    }

    func testUserFacingWorkspacesExcludeWorkspaceWithOnlyMacosHiddenWindows() {
        let focusedWorkspace = Workspace.get(byName: "focused")
        let hiddenOnlyWorkspace = Workspace.get(byName: "hidden-only")
        _ = TestWindow.new(id: 24, parent: hiddenOnlyWorkspace.macOsNativeHiddenAppsWindowsContainer)
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 25, parent: occupiedWorkspace.rootTilingContainer)

        let result = userFacingWorkspaces(
            [focusedWorkspace, hiddenOnlyWorkspace, occupiedWorkspace],
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertEqual(result, [occupiedWorkspace])
        XCTAssertFalse(workspaceHasSidebarVisibleWindows(hiddenOnlyWorkspace))
    }

    func testWorkspaceToLiveFocusSkipsMacosUnconventionalWindows() {
        let workspace = Workspace.get(byName: "focusable")
        let visibleWindow = TestWindow.new(id: 26, parent: workspace.rootTilingContainer)
        _ = TestWindow.new(id: 27, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        _ = TestWindow.new(id: 28, parent: workspace.macOsNativeFullscreenWindowsContainer)

        XCTAssertEqual(workspace.toLiveFocus().windowOrNil, visibleWindow)
    }

    func testFrozenFocusFallsBackToWorkspaceFocusWhenWindowStopsParticipatingInWorkspaceFocus() {
        let workspace = Workspace.get(byName: "focusable")
        let visibleWindow = TestWindow.new(id: 29, parent: workspace.rootTilingContainer)
        let hiddenWindow = TestWindow.new(id: 30, parent: workspace.macOsNativeHiddenAppsWindowsContainer)

        _ = setFocus(to: LiveFocus(windowOrNil: hiddenWindow, workspace: workspace))

        XCTAssertEqual(focus.workspace, workspace)
        XCTAssertEqual(focus.windowOrNil, visibleWindow)
    }

    func testRestorableWorkspacesExcludeEmptyWorkspace() {
        let emptyWorkspace = Workspace.get(byName: "empty")
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 3, parent: occupiedWorkspace.rootTilingContainer)

        XCTAssertEqual(restorableWorkspaces([emptyWorkspace, occupiedWorkspace]), [occupiedWorkspace])
    }

    func testCancelManipulatedWithMouseStateClearsDragTracking() {
        let workspace = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        setDraggedWindowAnchorRect(Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100), for: window.windowId)
        currentlyManipulatedWithMouseWindowId = window.windowId
        setCurrentMouseManipulationKind(.move)
        setCurrentMouseDragSubject(.group)
        setCurrentMouseTabDetachOrigin(.tabStrip)
        setCurrentMouseDragStartedInSidebar(true)

        cancelManipulatedWithMouseState()

        XCTAssertNil(currentlyManipulatedWithMouseWindowId)
        XCTAssertEqual(getCurrentMouseManipulationKind(), .none)
        XCTAssertEqual(getCurrentMouseDragSubject(), .window)
        XCTAssertEqual(getCurrentMouseTabDetachOrigin(), .window)
        XCTAssertFalse(getCurrentMouseDragStartedInSidebar())
        XCTAssertNil(draggedWindowAnchorRect(for: window.windowId))
    }

}
