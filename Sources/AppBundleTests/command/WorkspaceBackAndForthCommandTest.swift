@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceBackAndForthCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testWorkspaceBackAndForthDoesNotRecreateDeletedWorkspace() async throws {
        let initialWorkspace = focus.workspace
        _prevFocusedWorkspaceName = "2"

        let result = try await WorkspaceBackAndForthCommand(
            args: WorkspaceBackAndForthCmdArgs(rawArgs: []),
        ).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertEqual(focus.workspace, initialWorkspace)
        XCTAssertNil(Workspace.existing(byName: "2"))
    }
}
