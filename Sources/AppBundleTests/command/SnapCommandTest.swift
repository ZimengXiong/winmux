@testable import AppBundle
import Common
import XCTest

@MainActor
final class SnapCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseCommand() {
        testParseCommandSucc("snap left-half", SnapCmdArgs(rawArgs: [], action: .leftHalf))
        testParseCommandSucc("snap maximize", SnapCmdArgs(rawArgs: [], action: .maximize))
        testParseCommandFail("snap foo", msg: """
            ERROR: Can't parse 'foo'.
                   Possible values: (left-half|right-half|top-half|bottom-half|top-left|top-right|bottom-left|bottom-right|first-third|center-third|last-third|first-two-thirds|last-two-thirds|maximize)
            """)
    }

    func testSnapCommandAppliesRectangleRectInUnmanagedMode() async throws {
        config.enableWindowManagement = false
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(
            id: 1,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 40, topLeftY: 70, width: 300, height: 200),
        )
        XCTAssertTrue(window.focusWindow())

        let result = try await SnapCommand(args: SnapCmdArgs(rawArgs: [], action: .maximize)).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        let actualRect = try await window.getAxRect().orDie()
        let expectedRect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        XCTAssertEqual(actualRect.topLeftX, expectedRect.topLeftX)
        XCTAssertEqual(actualRect.topLeftY, expectedRect.topLeftY)
        XCTAssertEqual(actualRect.width, expectedRect.width)
        XCTAssertEqual(actualRect.height, expectedRect.height)
    }

    func testSnapCommandFailsWhenWindowManagementIsEnabled() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertTrue(window.focusWindow())

        let result = try await SnapCommand(args: SnapCmdArgs(rawArgs: [], action: .leftHalf)).run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
    }
}
