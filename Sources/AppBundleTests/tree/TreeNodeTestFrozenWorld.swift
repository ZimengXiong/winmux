@testable import AppBundle
import XCTest

extension TreeNodeTest {
    func testExitMacOsNativeUnconventionalStateRestoresWindowToPreviousWorkspaceWhileWorkspaceStaysAlive() async throws {
        let workspaceA = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        let workspaceB = Workspace.get(byName: "b")

        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspaceA.name)
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = workspaceB.focusWorkspace()

        Workspace.reconcileWorkspaceState()
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
        let tabGroup = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let fullscreenWindow = TestWindow.new(id: 11, parent: tabGroup, adaptiveWeight: 1)
        TestWindow.new(id: 12, parent: tabGroup, adaptiveWeight: 1)
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
                XCTAssertEqual(container.layout, .tabGroup)
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

    func testSnapshotCurrentFrozenWorldExcludesDetachedMinimizedWindow() {
        let workspace = Workspace.get(byName: "minimized")
        let window = TestWindow.new(id: 32, parent: workspace.rootTilingContainer)

        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
        window.nativeIsMacosMinimized = true
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)

        let frozenWorld = snapshotCurrentFrozenWorld()

        XCTAssertTrue(frozenWorld.windowIds.isEmpty)
        XCTAssertTrue(frozenWorld.workspaces.isEmpty)
    }

    func testRestoreFrozenWorldIfNeededUsesNativeFallbackWorkspaceForMissingVisibleWorkspace() async throws {
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
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(Workspace.existing(byName: emptyWorkspace.name))

        let didRestore = try await restoreFrozenWorldIfNeeded(frozenWorld, newlyDetectedWindow: window)
        XCTAssertTrue(didRestore)

        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertTrue(mainMonitor.activeWorkspace.isEffectivelyEmpty)
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
        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
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

        XCTAssertFalse(didRestore)
        XCTAssertEqual(window.nodeWorkspace, stagingWorkspace)
        XCTAssertTrue(stagingWorkspace.floatingWindows.contains(window))
        XCTAssertEqual(window.layoutReason, .standard)
    }

    func testRestoreFrozenWorldIfNeededKeepsStillMinimizedWindowInMinimizedContainer() async throws {
        let workspace = Workspace.get(byName: "restore")
        let window = TestWindow.new(id: 44, parent: workspace.rootTilingContainer)
        window.rememberMacOsLayoutOrigin(detachFromWorkspace: true)
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

        XCTAssertFalse(didRestore)
        XCTAssertEqual(window.nodeWorkspace, stagingWorkspace)
        XCTAssertTrue(stagingWorkspace.floatingWindows.contains(window))
        XCTAssertEqual(window.layoutReason, .standard)
    }
}
