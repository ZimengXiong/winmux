@testable import AppBundle
import Common
import XCTest

final class ListWorkspacesTest: XCTestCase {
    func testParse() {
        assertNotNil(parseCommand("list-workspaces --all").cmdOrNil)
        assertNil(parseCommand("list-workspaces --all --visible").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --visible").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --all").cmdOrNil)
        assertNil(parseCommand("list-workspaces --visible").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --visible --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --monitor focused").cmdOrNil)
        assertNil(parseCommand("list-workspaces --focused --monitor 2").cmdOrNil)
        assertNotNil(parseCommand("list-workspaces --all --format %{workspace}").cmdOrNil)
        assertEquals(parseCommand("list-workspaces --all --format %{workspace} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(parseCommand("list-workspaces --empty").errorOrNil, "Mandatory option is not specified (--all|--focused|--monitor)")
        assertEquals(parseCommand("list-workspaces --all --focused --monitor mouse").errorOrNil, "ERROR: Conflicting options: --all, --focused, --monitor")
    }

    @MainActor
    func testListWorkspacesUsesProjectLaneOrderInsteadOfRawNameSort() async throws {
        setUpWorkspacesForTests()
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)

        let io = CmdIo(stdin: .emptyStdin)
        let command = parseCommand("list-workspaces --all --format %{workspace}").cmdOrDie
        let succeeded = try await command.run(.defaultEnv, io)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(io.stdout.filter { $0 != "setUpWorkspacesForTests" }, ["10", "2"])
    }
}
