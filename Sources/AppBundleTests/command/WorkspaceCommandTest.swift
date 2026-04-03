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
