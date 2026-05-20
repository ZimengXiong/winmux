@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceLifecycleTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testReconcilePrunesUnfocusedEmptyWorkspacesWhenProjectHasOccupiedWorkspace() {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: occupied.rootTilingContainer)
        let adjacentEmpty = Workspace.get(byName: "2")
        adjacentEmpty.markAsTransientBlank()
        let extraEmpty = Workspace.get(byName: "3")
        extraEmpty.markAsTransientBlank()
        _ = occupied.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertEqual(emptyUserFacingWorkspaces(in: occupied.scope), [])
        _ = adjacentEmpty
    }

    func testReconcileKeepsOnlyVisibleWorkspaceWhenAllWorkspacesAreEmpty() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let visible = Workspace.get(byName: "2")
        visible.markAsAutomaticallyNamed()
        let last = Workspace.get(byName: "3")
        last.markAsAutomaticallyNamed()
        _ = visible.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: first.name))
        XCTAssertTrue(Workspace.existing(byName: visible.name) === visible)
        XCTAssertNil(Workspace.existing(byName: last.name))
        XCTAssertEqual(Workspace.all, [visible])
    }

    func testFocusedAdjacentBlankWorkspaceCreationReusesExistingEmptySlot() async throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: occupied.rootTilingContainer)
        _ = occupied.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        let existingBlank = try XCTUnwrap(Workspace.existing(byName: "2"))

        let blank = getOrCreateAdjacentBlankWorkspace(projectId: occupied.projectId, monitor: occupied.workspaceMonitor)

        XCTAssertTrue(blank === existingBlank)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testSidebarDragReusesRawAdjacentNameAfterUnfocusedBlankIsCollected() async throws {
        let sourceWorkspace = Workspace.get(byName: "1")
        sourceWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 3, parent: sourceWorkspace.rootTilingContainer)
        let movedWindow = TestWindow.new(id: 4, parent: sourceWorkspace.rootTilingContainer)
        _ = sourceWorkspace.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        let deletedBlank = try XCTUnwrap(Workspace.existing(byName: "2"))
        _ = sourceWorkspace.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(createWorkspaceFromSidebarDrag(sourceNode: movedWindow, sourceWindow: movedWindow))

        XCTAssertFalse(Workspace.existing(byName: deletedBlank.name) === deletedBlank)
        XCTAssertEqual(movedWindow.nodeWorkspace?.name, "2")
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertTrue(emptyUserFacingWorkspaces(in: sourceWorkspace.scope).isEmpty)
    }

    func testMovingLastProjectWindowAwayLeavesOneActiveEmptyProjectWorkspace() async throws {
        let defaultTarget = Workspace.get(byName: "default-target")
        _ = TestWindow.new(id: 5, parent: defaultTarget.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        let projectWindow = TestWindow.new(id: 6, parent: projectWorkspace.rootTilingContainer)
        _ = projectWindow.focusWindow()

        assertEquals(
            try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: defaultTarget.name))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, project.id)
        XCTAssertTrue(mainMonitor.activeWorkspace.isEffectivelyEmpty)
        XCTAssertEqual(emptyUserFacingWorkspaces(in: projectWorkspace.scope), [projectWorkspace])
    }

    func testWorkspaceNextFromExistingBlankDoesNotCreateAnotherBlank() async throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 7, parent: occupied.rootTilingContainer)
        _ = occupied.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )

        let result = try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
        XCTAssertEqual(emptyUserFacingWorkspaces(in: occupied.scope).map(\.name), ["2"])
    }

    func testEmptyAdjacentWorkspaceIsDeletedAfterLeavingIt() async throws {
        let occupied = Workspace.get(byName: "1")
        occupied.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 8, parent: occupied.rootTilingContainer)
        _ = occupied.focusWorkspace()

        assertEquals(
            try await WorkspaceCommand(args: WorkspaceCmdArgs(target: .relative(.next)))
                .run(.defaultEnv, .emptyStdin)
                .exitCode,
            0,
        )
        let emptyWorkspace = try XCTUnwrap(Workspace.existing(byName: "2"))

        _ = occupied.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: emptyWorkspace.name))
        XCTAssertEqual(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace), [occupied])
    }

    func testConnectingSecondMonitorCreatesVisibleWorkspaceForDefaultProject() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([main])
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        XCTAssertTrue(main.setActiveWorkspace(workspace))
        Workspace.reconcileWorkspaceState()

        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(main.activeWorkspace === workspace)
        XCTAssertNotNil(secondary.activeWorkspace)
        XCTAssertFalse(secondary.activeWorkspace === workspace)
        XCTAssertEqual(secondary.activeWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertTrue(secondary.activeWorkspace.isOrdinaryEmptySlot)
        XCTAssertEqual(Workspace.all.filter { $0.projectId == workspaceProjectDefaultId && !$0.isArchived }.count, 2)
    }

    func testEachMonitorKeepsAWorkspaceWhenWorkspacesSpanProjects() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let defaultWorkspace = Workspace.get(byName: "default")
        XCTAssertTrue(main.setActiveWorkspace(defaultWorkspace))
        let project = createWorkspaceProject()
        let projectWorkspace = createBlankWorkspace(projectId: project.id, monitor: secondary)
        XCTAssertTrue(secondary.setActiveWorkspace(projectWorkspace))

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(main.activeWorkspace === defaultWorkspace)
        XCTAssertTrue(secondary.activeWorkspace === projectWorkspace)
        XCTAssertEqual(defaultWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(projectWorkspace.projectId, project.id)
    }

    private func emptyUserFacingWorkspaces(in scope: WorkspaceScope) -> [Workspace] {
        userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
            .filter { $0.scope == scope && $0.isOrdinaryEmptySlot }
    }
}
