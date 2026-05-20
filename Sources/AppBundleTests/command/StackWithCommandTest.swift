@testable import AppBundle
import Common
import XCTest

@MainActor
final class StackWithCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testStackWithRightCreatesTabGroupContainer() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        try await StackWithCommand(args: StackWithCmdArgs(rawArgs: [], direction: .right)).run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([
            .window(0),
            .v_tab_group([
                .window(2),
                .window(1),
            ]),
        ]))
    }

    func testStackWithLeftSplitsFocusedWindowOutOfTabGroup() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer(parent: $0, adaptiveWeight: 1, .v, .tabGroup, index: INDEX_BIND_LAST).apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            }
        }

        try await StackWithCommand(args: StackWithCmdArgs(rawArgs: [], direction: .left)).run(.defaultEnv, .emptyStdin)

        assertEquals(root.layoutDescription, .h_tiles([
            .window(1),
            .window(0),
        ]))
    }
}
