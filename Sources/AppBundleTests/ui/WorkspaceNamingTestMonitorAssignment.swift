@testable import AppBundle
import AppKit
import Common
import XCTest

extension WorkspaceNamingTest {
    func testMovingWorkspaceToAnotherMonitorKeepsSourceMonitorInSameProject() async throws {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Left",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Right",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: main))
        XCTAssertTrue(projectWorkspace.focusWorkspace())

        var args = MoveWorkspaceToMonitorCmdArgs(rawArgs: [])
        args.target = .initialized(.relative(.next))
        let result = try await MoveWorkspaceToMonitorCommand(args: args).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertTrue(secondary.activeWorkspace === projectWorkspace)
        XCTAssertEqual(main.activeWorkspace.projectId, project.id)
        XCTAssertTrue(main.activeWorkspace !== projectWorkspace)
    }

    func testProjectFocusHoldIgnoresNativeFocusFromOtherProject() throws {
        let defaultWorkspace = focus.workspace
        let defaultWindow = TestWindow.new(id: 301, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = createBlankWorkspace(projectId: project.id, monitor: mainMonitor)
        projectWorkspace.markAsSidebarManaged()
        XCTAssertTrue(projectWorkspace.focusWorkspace())

        holdFocusOnWorkspaceProject(project.id, for: 60)
        updateFocusCache(defaultWindow)

        XCTAssertTrue(focus.workspace === projectWorkspace)

        clearFocusOnWorkspaceProjectHold(project.id)
        updateFocusCache(defaultWindow)

        XCTAssertTrue(focus.workspace === defaultWorkspace)
    }

    func testSummoningWorkspaceToFocusedMonitorKeepsSourceMonitorInSameProject() async throws {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Left",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Right",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: secondary))
        let focusedWorkspace = Workspace.get(byName: "focused")
        XCTAssertTrue(main.setActiveWorkspace(focusedWorkspace))
        XCTAssertTrue(focusedWorkspace.focusWorkspace())

        let result = try await parseCommand("summon-workspace \(projectWorkspace.name)").cmdOrDie
            .run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertTrue(main.activeWorkspace === projectWorkspace)
        XCTAssertTrue(focus.workspace === projectWorkspace)
        XCTAssertEqual(secondary.activeWorkspace.projectId, project.id)
        XCTAssertTrue(secondary.activeWorkspace !== projectWorkspace)
    }

    func testWorkspaceToMonitorForceAssignmentRejectsWrongMonitor() {
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
        config.workspaceToMonitorForceAssignment["forced"] = [.sequenceNumber(2)]
        let workspace = Workspace.get(byName: "forced")

        XCTAssertFalse(main.setActiveWorkspace(workspace))
        XCTAssertTrue(secondary.setActiveWorkspace(workspace))
        XCTAssertTrue(secondary.activeWorkspace === workspace)
    }

    func testReconcileMovesVisibleWorkspaceToNewForceAssignedMonitor() {
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
        let workspace = Workspace.get(byName: "forced")
        _ = TestWindow.new(id: 214, parent: workspace.rootTilingContainer)
        XCTAssertTrue(main.setActiveWorkspace(workspace))
        config.workspaceToMonitorForceAssignment[workspace.name] = [.sequenceNumber(2)]

        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(secondary.activeWorkspace === workspace)
        XCTAssertFalse(main.activeWorkspace === workspace)
        XCTAssertEqual(workspace.preferredMonitorPointForTesting, secondary.rect.topLeftCorner)
    }

    func testLaneFallbackIgnoresEmptyWorkspaceForcedToAnotherMonitor() {
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
        _ = TestWindow.new(id: 213, parent: focus.workspace.rootTilingContainer)
        let forcedElsewhere = Workspace.get(byName: "forced")
        forcedElsewhere.assignLane(DisplayLaneId(main))
        config.workspaceToMonitorForceAssignment[forcedElsewhere.name] = [.sequenceNumber(2)]

        let fallback = getOrCreateLaneFallbackWorkspace(projectId: workspaceProjectDefaultId, for: main)

        XCTAssertFalse(fallback === forcedElsewhere)
        XCTAssertEqual(fallback.preferredMonitorPointForTesting, main.rect.topLeftCorner)
        XCTAssertEqual(fallback.workspaceMonitor.rect.topLeftCorner, main.rect.topLeftCorner)
    }

    func testGcMonitorsReconcilesChangedMonitorPointsWithSameMonitorCount() {
        let oldMain = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let oldSecondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([oldMain, oldSecondary])
        let workspace = Workspace.get(byName: "visible")
        _ = TestWindow.new(id: 21, parent: workspace.rootTilingContainer)
        XCTAssertTrue(oldMain.setActiveWorkspace(workspace))

        let newMain = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 100, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 100, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let newSecondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 2020, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 2020, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([newMain, newSecondary])

        gcMonitors()

        XCTAssertTrue(newMain.activeWorkspace === workspace)
    }

    func testGcMonitorsIgnoresInactiveLanesWhenPreservingVisibleWorkspace() {
        let oldMain = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([oldMain])
        let visibleWorkspace = Workspace.get(byName: "visible")
        _ = TestWindow.new(id: 22, parent: visibleWorkspace.rootTilingContainer)
        XCTAssertTrue(oldMain.setActiveWorkspace(visibleWorkspace))
        let inactiveWorkspace = Workspace.get(byName: "inactive")
        inactiveWorkspace.assignLane(DisplayLaneId(topLeftCorner: CGPoint(x: 100, y: 0)))

        let newMain = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 100, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 100, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([newMain])

        gcMonitors()

        XCTAssertTrue(newMain.activeWorkspace === visibleWorkspace)
        XCTAssertTrue(inactiveWorkspace.isEffectivelyEmpty)
        XCTAssertFalse(inactiveWorkspace.isVisible)
    }

    func testLaneFallbackWorkspaceDoesNotForgetActiveProject() throws {
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        XCTAssertTrue(projectWorkspace.isVisible)

        let fallback = activateLaneFallbackWorkspaceForTests(on: mainMonitor)
        XCTAssertEqual(fallback.projectId, project.id)
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, project.id)
        XCTAssertTrue(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).contains(mainMonitor.activeWorkspace))
    }

    func testClosingLastWindowKeepsOneWorkspaceInActiveProject() throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 19, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        let projectWindow = TestWindow.new(id: 20, parent: projectWorkspace.rootTilingContainer)

        Workspace.reconcileWorkspaceState()
        projectWindow.unbindFromParent()
        Workspace.reconcileWorkspaceState()

        XCTAssertTrue(projectWorkspace.isVisible)
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
        XCTAssertFalse(workspaceHasSidebarVisibleWindows(projectWorkspace))
        XCTAssertTrue(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).contains(projectWorkspace))
        XCTAssertEqual(
            userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
                .filter { $0.scope == workspaceScope(projectId: project.id, monitor: mainMonitor) },
            [projectWorkspace],
        )
    }
}
