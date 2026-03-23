@testable import AppBundle
import Common
import XCTest

@MainActor
final class SummonWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
    }

    func testSummonDoesNotCreateMissingWorkspace() async throws {
        let args = SummonWorkspaceCmdArgs(rawArgs: [])
            .copy(\.target, .initialized(.parse("2").getOrDie()))
        let result = try await SummonWorkspaceCommand(args: args).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }
}
