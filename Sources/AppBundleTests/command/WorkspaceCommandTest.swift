@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseWorkspaceCommand() {
        testParseCommandFail("workspace my mail", msg: "ERROR: Unknown argument 'mail'")
        testParseCommandFail("workspace 'my mail'", msg: "ERROR: Whitespace characters are forbidden in workspace names")
        assertEquals(parseCommand("workspace").errorOrNil, "ERROR: Argument '(<workspace-name>|next|prev)' is mandatory")
        testParseCommandSucc("workspace next", WorkspaceCmdArgs(target: .relative(.next)))
        testParseCommandSucc("workspace --auto-back-and-forth W", WorkspaceCmdArgs(target: .direct(.parse("W").getOrDie()), autoBackAndForth: true))
        assertEquals(parseCommand("workspace --wrap-around W").errorOrNil, "--wrapAround requires using (next|prev) argument")
        assertEquals(parseCommand("workspace --auto-back-and-forth next").errorOrNil, "--auto-back-and-forth is incompatible with (next|prev)")
        testParseCommandSucc("workspace next --wrap-around", WorkspaceCmdArgs(target: .relative(.next), wrapAround: true))
        assertEquals(parseCommand("workspace --stdin foo").errorOrNil, "--stdin and --no-stdin require using (next|prev) argument")
        testParseCommandSucc("workspace --stdin next", WorkspaceCmdArgs(target: .relative(.next)).copy(\.explicitStdinFlag, true))
        testParseCommandSucc("workspace --no-stdin next", WorkspaceCmdArgs(target: .relative(.next)).copy(\.explicitStdinFlag, false))
    }

    func testDirectWorkspaceFocusDoesNotCreateMissingWorkspace() async throws {
        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testDirectWorkspaceFocusCreatesNextBlankNumericWorkspace() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertEqual(workspaceDisplayName("2"), "Workspace 2")
    }

    func testDirectWorkspaceFocusDoesNotSkipBlankNumericWorkspace() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("3").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testDirectWorkspaceFocusDoesNotCreateMultipleHopsAfterBlankIsCollected() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 20, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()
        assertEquals(
            try await WorkspaceCommand(
                args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
            ).run(.defaultEnv, .emptyStdin).exitCode,
            0,
        )
        _ = workspace1.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        XCTAssertNil(Workspace.existing(byName: "2"))

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("3").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testDirectWorkspaceShortcutUsesProjectLaneOrderInsteadOfRawNameSort() async throws {
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 21, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 22, parent: second.rootTilingContainer)
        _ = second.focusWorkspace()

        let focusFirst = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("1").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)
        assertEquals(focusFirst.exitCode, 0)
        XCTAssertTrue(focus.workspace === first)

        let focusSecond = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)
        assertEquals(focusSecond.exitCode, 0)
        XCTAssertTrue(focus.workspace === second)
    }

    func testDirectWorkspaceFocusFillsDisplayIndexGapBeforeAppending() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 23, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 24, parent: thirdRaw.rootTilingContainer)
        _ = first.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("3").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertNil(Workspace.existing(byName: "4"))
        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(thirdRaw.name), "Workspace 2")
        XCTAssertEqual(workspaceDisplayName("2"), "Workspace 3")
    }

    func testNextWorkspaceAfterRawNameGapCreatesRawTwoNotRawFour() async throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 25, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 26, parent: thirdRaw.rootTilingContainer)
        _ = thirdRaw.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertNil(Workspace.existing(byName: "4"))
        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(thirdRaw.name), "Workspace 2")
        XCTAssertEqual(workspaceDisplayName("2"), "Workspace 3")
    }

    func testBlankNumericWorkspaceIsDeletedAfterLeavingItEmpty() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 3, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        assertEquals(
            try await WorkspaceCommand(
                args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
            ).run(.defaultEnv, .emptyStdin).exitCode,
            0,
        )

        _ = workspace1.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertEqual(workspaceDisplayName("1"), "Workspace 1")
    }

    func testWorkspaceNextCreatesBlankNumericWorkspaceAtRightEdge() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 4, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.name, "2")
        XCTAssertEqual(workspaceDisplayName("2"), "Workspace 2")
    }

    func testWorkspaceNextBlankNumericWorkspaceIsDeletedAfterLeavingItEmpty() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 5, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        assertEquals(
            try await WorkspaceCommand(
                args: WorkspaceCmdArgs(target: .relative(.next)),
            ).run(.defaultEnv, .emptyStdin).exitCode,
            0,
        )

        _ = workspace1.focusWorkspace()
        Workspace.reconcileWorkspaceState()

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertEqual(workspaceDisplayName("1"), "Workspace 1")
    }

    func testDirectWorkspaceShortcutPrefersActiveProjectDisplayIndex() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 51, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        XCTAssertTrue(TestWindow.new(id: 56, parent: projectWorkspace.rootTilingContainer).focusWindow())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("1").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertTrue(focus.workspace === projectWorkspace)
        XCTAssertEqual(focus.workspace.projectId, project.id)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Workspace 1")
    }

    func testDirectWorkspaceShortcutCreatesNextWorkspaceInsideActiveProject() async throws {
        let defaultWorkspace1 = Workspace.get(byName: "1")
        defaultWorkspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 52, parent: defaultWorkspace1.rootTilingContainer)
        let defaultWorkspace2 = Workspace.get(byName: "2")
        defaultWorkspace2.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 53, parent: defaultWorkspace2.rootTilingContainer)
        let project = createWorkspaceProject()
        let firstProjectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        XCTAssertTrue(TestWindow.new(id: 57, parent: firstProjectWorkspace.rootTilingContainer).focusWindow())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, project.id)
        XCTAssertFalse(focus.workspace === defaultWorkspace2)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Workspace 2")
    }

    func testWorkspaceNextCreatesWorkspaceInsideActiveProject() async throws {
        let defaultWorkspace1 = Workspace.get(byName: "1")
        defaultWorkspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 54, parent: defaultWorkspace1.rootTilingContainer)
        let defaultWorkspace2 = Workspace.get(byName: "2")
        defaultWorkspace2.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 55, parent: defaultWorkspace2.rootTilingContainer)
        let project = createWorkspaceProject()
        let firstProjectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        XCTAssertTrue(TestWindow.new(id: 58, parent: firstProjectWorkspace.rootTilingContainer).focusWindow())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next)),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace.projectId, project.id)
        XCTAssertFalse(focus.workspace === defaultWorkspace2)
        XCTAssertEqual(workspaceDisplayName(focus.workspace.name), "Workspace 2")
    }

    func testWorkspaceNextDoesNotCreateBlankWorkspaceWhenWrapping() async throws {
        let workspace1 = Workspace.get(byName: "1")
        workspace1.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 6, parent: workspace1.rootTilingContainer)
        _ = workspace1.focusWorkspace()

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .relative(.next), wrapAround: true),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testDirectWorkspaceFocusDoesNotCreateConfiguredPersistentWorkspace() async throws {
        config.persistentWorkspaces = ["2"]

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }

    func testDirectWorkspaceFocusIgnoresWorkspaceWithOnlyMacosFullscreenWindows() async throws {
        let initialWorkspace = focus.workspace
        let hiddenWorkspace = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 10, parent: hiddenWorkspace.macOsNativeFullscreenWindowsContainer)

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertEqual(focus.workspace, initialWorkspace)
    }

    func testWorkspaceSwitchRefreshesClosedWindowsCacheVisibleWorkspaceSnapshot() async throws {
        let workspace1 = Workspace.get(byName: "1")
        let window1 = TestWindow.new(id: 11, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 12, parent: workspace2.rootTilingContainer)
        _ = workspace1.focusWorkspace()
        replaceClosedWindowsCache(snapshotCurrentFrozenWorld())

        let result = try await WorkspaceCommand(
            args: WorkspaceCmdArgs(target: .direct(.parse("2").getOrDie())),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(mainMonitor.activeWorkspace, workspace2)

        let didRestore = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window1)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(mainMonitor.activeWorkspace, workspace2)
    }

    func testWorkspaceNextUsesCurrentWorkspacePositionWhenFilteredStdinOmitsIt() async throws {
        let workspace1 = Workspace.get(byName: "1")
        _ = TestWindow.new(id: 21, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 22, parent: workspace2.rootTilingContainer)
        let workspace3 = Workspace.get(byName: "3")
        let workspace4 = Workspace.get(byName: "4")
        _ = TestWindow.new(id: 24, parent: workspace4.rootTilingContainer)
        let workspace5 = Workspace.get(byName: "5")
        _ = TestWindow.new(id: 25, parent: workspace5.rootTilingContainer)
        _ = workspace3.focusWorkspace()

        let result = try await parseCommand("workspace --stdin next").cmdOrDie.run(
            .defaultEnv,
            CmdStdin("1\n2\n4\n5"),
        )

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace4)
    }

    func testWorkspacePrevUsesCurrentWorkspacePositionWhenFilteredStdinOmitsIt() async throws {
        let workspace1 = Workspace.get(byName: "1")
        _ = TestWindow.new(id: 31, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 32, parent: workspace2.rootTilingContainer)
        let workspace3 = Workspace.get(byName: "3")
        let workspace4 = Workspace.get(byName: "4")
        _ = TestWindow.new(id: 34, parent: workspace4.rootTilingContainer)
        let workspace5 = Workspace.get(byName: "5")
        _ = TestWindow.new(id: 35, parent: workspace5.rootTilingContainer)
        _ = workspace3.focusWorkspace()

        let result = try await parseCommand("workspace --stdin prev").cmdOrDie.run(
            .defaultEnv,
            CmdStdin("1\n2\n4\n5"),
        )

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace2)
    }

    func testWorkspaceNextDeduplicatesStdinWorkspaceList() async throws {
        let workspace1 = Workspace.get(byName: "1")
        _ = TestWindow.new(id: 41, parent: workspace1.rootTilingContainer)
        let workspace2 = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 42, parent: workspace2.rootTilingContainer)
        let workspace3 = Workspace.get(byName: "3")
        _ = TestWindow.new(id: 43, parent: workspace3.rootTilingContainer)
        _ = workspace2.focusWorkspace()

        let result = try await parseCommand("workspace --stdin next").cmdOrDie.run(
            .defaultEnv,
            CmdStdin("1\n2\n2\n3"),
        )

        assertEquals(result.exitCode, 0)
        XCTAssertEqual(focus.workspace, workspace3)
    }
}
