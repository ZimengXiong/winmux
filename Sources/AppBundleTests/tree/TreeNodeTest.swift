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

    func testGarbageCollectUnusedWorkspacesRemovesSidebarManagedEmptyWorkspaceImmediately() {
        let workspace = Workspace.get(byName: "draft")
        workspace.markAsSidebarManaged()

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertFalse(Workspace.all.contains(workspace))
    }

    func testGarbageCollectUnusedWorkspacesRemovesPersistentEmptyWorkspace() {
        config.persistentWorkspaces = ["keep"]
        let workspace = Workspace.get(byName: "keep")

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertFalse(Workspace.all.contains(workspace))
    }

    func testGarbageCollectUnusedWorkspacesKeepsFreshFocusedEmptyWorkspace() {
        let workspace = Workspace.get(byName: "draft")
        workspace.markAsSidebarManaged()
        _ = workspace.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertTrue(Workspace.all.contains(workspace))
        XCTAssertEqual(focus.workspace, workspace)
    }

    func testGarbageCollectUnusedWorkspacesDeletesFocusedEmptyWorkspaceWhenNotFresh() {
        let workspace = Workspace.get(byName: "empty")
        _ = workspace.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertNil(Workspace.existing(byName: workspace.name))
        XCTAssertNotEqual(focus.workspace.name, workspace.name)
        XCTAssertFalse(isUserFacingWorkspace(focus.workspace, focusedWorkspace: focus.workspace))
    }

    func testGarbageCollectUnusedWorkspacesDeletesFreshEmptyWorkspaceAfterLeavingIt() {
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 101, parent: occupiedWorkspace.rootTilingContainer)
        let draftWorkspace = Workspace.get(byName: "draft")
        draftWorkspace.markAsSidebarManaged()
        _ = draftWorkspace.focusWorkspace()
        _ = occupiedWorkspace.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertNil(Workspace.existing(byName: draftWorkspace.name))
    }

    func testGarbageCollectUnusedWorkspacesKeepsWorkspaceWithOnlyMinimizedWindow() {
        let workspace = Workspace.get(byName: "kept")
        let window = TestWindow.new(id: 111, parent: workspace.rootTilingContainer)
        let otherWorkspace = Workspace.get(byName: "other")

        window.rememberMacOsLayoutOrigin()
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = otherWorkspace.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertEqual(window.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name))
        XCTAssertEqual(Workspace.existing(byName: workspace.name), workspace)
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

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertEqual(nextSidebarDraftWorkspaceName(), "__sidebar_draft_workspace_1")
    }

    func testNextSidebarDraftWorkspaceNameClearsStalePersistedDraftLabelBeforeReuse() {
        config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"] = "Old Name"

        XCTAssertEqual(nextSidebarDraftWorkspaceName(), "__sidebar_draft_workspace_1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"])
    }

    func testGarbageCollectUnusedWorkspacesClearsStaleDraftWorkspaceLabel() {
        config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"] = "Old Name"
        _ = Workspace.get(byName: "__sidebar_draft_workspace_1")

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertNil(config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_1"])
        XCTAssertEqual(workspaceDisplayName("__sidebar_draft_workspace_1"), "Workspace 1")
    }

    func testGarbageCollectUnusedWorkspacesClearsOrphanedDraftWorkspaceLabel() {
        config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_7"] = "Old Name"

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertNil(config.workspaceSidebar.workspaceLabels["__sidebar_draft_workspace_7"])
        XCTAssertEqual(workspaceDisplayName("__sidebar_draft_workspace_7"), "Workspace 7")
    }

    func testWorkspaceDisplayNameUsesSidebarDraftFallback() {
        XCTAssertEqual(workspaceDisplayName("__sidebar_draft_workspace_4"), "Workspace 4")
    }

    func testShouldShowWorkspaceInSidebarExcludesPersistentEmptyWorkspace() {
        config.persistentWorkspaces = ["persistent"]
        let persistentWorkspace = Workspace.get(byName: "persistent")

        XCTAssertFalse(
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

    func testUserFacingWorkspacesIncludeFreshFocusedEmptyWorkspace() {
        let focusedWorkspace = Workspace.get(byName: "focused")
        focusedWorkspace.markAsSidebarManaged()
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        _ = TestWindow.new(id: 202, parent: occupiedWorkspace.rootTilingContainer)

        let result = userFacingWorkspaces(
            [focusedWorkspace, occupiedWorkspace],
            focusedWorkspace: focusedWorkspace,
        )

        XCTAssertEqual(result, [focusedWorkspace, occupiedWorkspace])
    }

    func testMaterializeWorkspaceForUserWindowReplacesInternalStub() {
        let emptyWorkspace = Workspace.get(byName: "empty")
        _ = emptyWorkspace.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()

        let internalStub = focus.workspace
        let materializedWorkspace = materializeWorkspaceForUserWindowIfNeeded(internalStub)

        XCTAssertNotEqual(materializedWorkspace, internalStub)
        XCTAssertFalse(materializedWorkspace.isSystemStub)
        XCTAssertEqual(materializedWorkspace.name, "1")
        XCTAssertEqual(materializedWorkspace.workspaceMonitor.activeWorkspace, materializedWorkspace)
    }

    func testMaterializedWorkspaceNamesReuseDeletedAutomaticName() {
        let firstStub = Workspace.get(byName: "__internal_stub_workspace_1")
        firstStub.markAsSystemStub()
        let firstMaterialized = materializeWorkspaceForUserWindowIfNeeded(firstStub)
        XCTAssertEqual(firstMaterialized.name, "1")

        Workspace.garbageCollectUnusedWorkspaces()

        let secondStub = Workspace.get(byName: "__internal_stub_workspace_2")
        secondStub.markAsSystemStub()
        let secondMaterialized = materializeWorkspaceForUserWindowIfNeeded(secondStub)
        XCTAssertEqual(secondMaterialized.name, "1")
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

    func testExitMacOsNativeUnconventionalStateRestoresWindowToPreviousWorkspaceWhileWorkspaceStaysAlive() async throws {
        let workspaceA = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        let workspaceB = Workspace.get(byName: "b")

        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspaceA.name)
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = workspaceB.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertEqual(Workspace.existing(byName: workspaceA.name), workspaceA)

        try await exitMacOsNativeUnconventionalState(
            window: window,
            prevParentKind: .tilingContainer,
            prevWorkspaceName: workspaceA.name,
            workspace: workspaceB,
        )

        let restoredWorkspace = Workspace.existing(byName: workspaceA.name).orDie()
        XCTAssertEqual(window.nodeWorkspace, restoredWorkspace)
        XCTAssertTrue(restoredWorkspace.rootTilingContainer.children.contains(window))
        XCTAssertEqual(restoredWorkspace.preferredMonitorPointForTesting, workspaceB.workspaceMonitor.rect.topLeftCorner)
    }

    func testPersistedFrozenWorldCodableRoundTrip() throws {
        let workspace = Workspace.get(byName: "1")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .accordion, index: 0)
        let fullscreenWindow = TestWindow.new(id: 11, parent: accordion, adaptiveWeight: 1)
        TestWindow.new(id: 12, parent: accordion, adaptiveWeight: 1)
        fullscreenWindow.isFullscreen = true
        fullscreenWindow.noOuterGapsInFullscreen = true
        fullscreenWindow.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [11, 12],
        )

        let data = try JSONEncoder().encode(frozenWorld)
        let decoded = try JSONDecoder().decode(FrozenWorld.self, from: data)

        XCTAssertEqual(decoded.windowIds, [11, 12])
        XCTAssertEqual(decoded.workspaces.count, 1)

        let frozenChild = try XCTUnwrap(decoded.workspaces.first?.rootTilingNode.children.first)
        switch frozenChild {
            case .container(let container):
                XCTAssertEqual(container.layout, .accordion)
                XCTAssertEqual(container.orientation, .h)
                XCTAssertEqual(container.children.count, 2)
                let fullscreenChild = try XCTUnwrap(container.children.first)
                guard case .window(let decodedWindow) = fullscreenChild else {
                    return XCTFail("Expected fullscreen window leaf in persisted frozen world")
                }
                XCTAssertTrue(decodedWindow.isFullscreen)
                XCTAssertTrue(decodedWindow.noOuterGapsInFullscreen)
                XCTAssertEqual(decodedWindow.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name))
            case .window:
                XCTFail("Expected nested container in persisted frozen world")
        }
    }

    func testSnapshotCurrentFrozenWorldIncludesWorkspaceOwnedMinimizedWindow() {
        let workspace = Workspace.get(byName: "minimized")
        let window = TestWindow.new(id: 32, parent: workspace.rootTilingContainer)

        window.rememberMacOsLayoutOrigin()
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = snapshotCurrentFrozenWorld()

        XCTAssertEqual(frozenWorld.windowIds, [window.windowId])
        XCTAssertEqual(frozenWorld.workspaces.map(\.name), [workspace.name])
        XCTAssertEqual(frozenWorld.workspaces.singleOrNil()?.macosUnconventionalWindows.map(\.id), [window.windowId])
    }

    func testRestoreFrozenWorldIfNeededDoesNotReviveEmptyVisibleWorkspace() async throws {
        let occupiedWorkspace = Workspace.get(byName: "occupied")
        let window = TestWindow.new(id: 31, parent: occupiedWorkspace.rootTilingContainer)
        let emptyWorkspace = Workspace.get(byName: "empty")
        _ = emptyWorkspace.focusWorkspace()

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(occupiedWorkspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [window.windowId],
        )

        _ = occupiedWorkspace.focusWorkspace()
        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertNil(Workspace.existing(byName: emptyWorkspace.name))

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)
        XCTAssertTrue(didRestore)

        XCTAssertNil(Workspace.existing(byName: emptyWorkspace.name))
        XCTAssertTrue(mainMonitor.activeWorkspace.isSystemStub)
        XCTAssertTrue(mainMonitor.activeWorkspace !== occupiedWorkspace)
    }

    func testRestoreFrozenWorldIfNeededRestoresWindowFullscreenState() async throws {
        let workspace = Workspace.get(byName: "restore")
        let tiled = TestWindow.new(id: 41, parent: workspace.rootTilingContainer)
        let floating = TestWindow.new(id: 42, parent: workspace)
        tiled.isFullscreen = true
        tiled.noOuterGapsInFullscreen = true
        floating.isFullscreen = true
        floating.noOuterGapsInFullscreen = false

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [tiled.windowId, floating.windowId],
        )

        tiled.isFullscreen = false
        tiled.noOuterGapsInFullscreen = false
        floating.isFullscreen = false
        floating.noOuterGapsInFullscreen = true

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: tiled)

        XCTAssertTrue(didRestore)
        XCTAssertTrue(tiled.isFullscreen)
        XCTAssertTrue(tiled.noOuterGapsInFullscreen)
        XCTAssertTrue(floating.isFullscreen)
        XCTAssertFalse(floating.noOuterGapsInFullscreen)
    }

    func testRestoreFrozenWorldIfNeededRetilesRestoredMinimizedWindowAfterNativeUnminimize() async throws {
        let workspace = Workspace.get(byName: "restore")
        let window = TestWindow.new(id: 43, parent: workspace.rootTilingContainer)
        window.rememberMacOsLayoutOrigin()
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [window.windowId],
        )

        let stagingWorkspace = Workspace.get(byName: "staging")
        window.nativeIsMacosMinimized = false
        window.layoutReason = .standard
        window.bindAsFloatingWindow(to: stagingWorkspace)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(window.nodeWorkspace, workspace)
        XCTAssertTrue(workspace.rootTilingContainer.children.contains(window))
        XCTAssertEqual(window.layoutReason, .standard)
    }

    func testRestoreFrozenWorldIfNeededKeepsStillMinimizedWindowInMinimizedContainer() async throws {
        let workspace = Workspace.get(byName: "restore")
        let window = TestWindow.new(id: 44, parent: workspace.rootTilingContainer)
        window.rememberMacOsLayoutOrigin()
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = FrozenWorld(
            workspaces: [FrozenWorkspace(workspace)],
            monitors: monitors.map(FrozenMonitor.init),
            windowIds: [window.windowId],
        )

        let stagingWorkspace = Workspace.get(byName: "staging")
        window.layoutReason = .standard
        window.bindAsFloatingWindow(to: stagingWorkspace)

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)

        XCTAssertTrue(didRestore)
        XCTAssertTrue(window.parent === macosMinimizedWindowsContainer)
        XCTAssertEqual(window.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name))
        XCTAssertEqual(Workspace.existing(byName: workspace.name), workspace)
    }
}
