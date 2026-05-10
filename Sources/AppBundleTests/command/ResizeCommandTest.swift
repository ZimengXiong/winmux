@testable import AppBundle
import Common
import XCTest

@MainActor
final class ResizeCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseCommand() {
        testParseCommandSucc("resize smart +10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .add(10)))
        testParseCommandSucc("resize smart -10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .subtract(10)))
        testParseCommandSucc("resize smart 10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .set(10)))

        testParseCommandSucc("resize smart-opposite +10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .add(10)))
        testParseCommandSucc("resize smart-opposite -10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .subtract(10)))
        testParseCommandSucc("resize smart-opposite 10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .set(10)))

        testParseCommandSucc("resize height 10", ResizeCmdArgs(rawArgs: [], dimension: .height, units: .set(10)))
        testParseCommandSucc("resize width 10", ResizeCmdArgs(rawArgs: [], dimension: .width, units: .set(10)))

        testParseCommandFail("resize s 10", msg: """
            ERROR: Can't parse 's'.
                   Possible values: (width|height|smart|smart-opposite)
            """)
        testParseCommandFail("resize smart foo", msg: "ERROR: <number> argument must be a number")
    }

    func testResizeWidthAddsWeightToFocusedWindowAndSubtractsFromSiblings() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let focused = TestWindow.new(id: 1, parent: root, adaptiveWeight: 10)
        let sibling = TestWindow.new(id: 2, parent: root, adaptiveWeight: 10)
        _ = focused.focusWindow()

        let result = try await parseCommand("resize width +4").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        assertEquals(focused.hWeight, 14)
        assertEquals(sibling.hWeight, 6)
    }

    func testResizeHeightUsesVerticalAncestorForFocusedWindow() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        var focused: Window!
        var verticalSibling: Window!
        let focusedContainer = TilingContainer.newVTiles(parent: root, adaptiveWeight: 8).apply {
            focused = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 6)
            verticalSibling = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 6)
            _ = focused.focusWindow()
        }
        let siblingContainer = TilingContainer.newVTiles(parent: root, adaptiveWeight: 12)
        TestWindow.new(id: 3, parent: siblingContainer, adaptiveWeight: 1)

        let result = try await parseCommand("resize height 10").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        assertEquals(focused.vWeight, 10)
        assertEquals(verticalSibling.vWeight, 2)
        assertEquals(focusedContainer.hWeight, 8)
        assertEquals(siblingContainer.hWeight, 12)
    }

    func testResizeFloatingWindowReturnsError() async throws {
        let workspace = Workspace.get(byName: name)
        _ = TestWindow.new(id: 1, parent: workspace, adaptiveWeight: WEIGHT_AUTO).focusWindow()

        let result = try await parseCommand("resize width +1").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        assertEquals(
            result.stderr,
            ["resize command doesn't support floating windows yet https://github.com/nikitabobko/WinMux/issues/9"],
        )
    }
}
