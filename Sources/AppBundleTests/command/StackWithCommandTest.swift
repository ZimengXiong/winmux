@testable import AppBundle
import Common
import XCTest

@MainActor
final class StackWithCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testStackWithRightCreatesAccordionContainer() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await StackWithCommand(args: StackWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_accordion([
                .window(2),
                .window(1),
            ]),
        ]))
    }
}
