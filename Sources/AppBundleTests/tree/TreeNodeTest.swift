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

    func testGarbageCollectUnusedWorkspacesKeepsPersistentWorkspace() {
        config.persistentWorkspaces = ["keep"]
        let workspace = Workspace.get(byName: "keep")

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertTrue(Workspace.all.contains(workspace))
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

    func testExitMacOsNativeUnconventionalStateRestoresWindowToPreviousWorkspaceAfterAutoDestroy() async throws {
        let workspaceA = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        let workspaceB = Workspace.get(byName: "b")

        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspaceA.name)
        window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = workspaceB.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertNil(Workspace.existing(byName: workspaceA.name))

        try await exitMacOsNativeUnconventionalState(
            window: window,
            prevParentKind: .tilingContainer,
            prevWorkspaceName: workspaceA.name,
            workspace: workspaceB,
        )

        let restoredWorkspace = Workspace.get(byName: workspaceA.name)
        XCTAssertEqual(window.nodeWorkspace, restoredWorkspace)
        XCTAssertTrue(restoredWorkspace.rootTilingContainer.children.contains(window))
    }

    func testPersistedFrozenWorldCodableRoundTrip() throws {
        let workspace = Workspace.get(byName: "1")
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .accordion, index: 0)
        TestWindow.new(id: 11, parent: accordion, adaptiveWeight: 1)
        TestWindow.new(id: 12, parent: accordion, adaptiveWeight: 1)

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
            case .window:
                XCTFail("Expected nested container in persisted frozen world")
        }
    }
}
