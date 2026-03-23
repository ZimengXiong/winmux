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
}
