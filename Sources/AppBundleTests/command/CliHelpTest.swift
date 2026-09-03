@testable import Cli
import Common
import Foundation
import XCTest

final class CliHelpTest: XCTestCase {
    func testEveryCliCommandAppearsExactlyOnceInTopLevelHelp() {
        let advertisedCommands = subcommandDescriptions.map {
            $0[0].trimmingCharacters(in: .whitespaces)
        }
        let expectedCommands = CmdKind.allCases
            .filter { $0 != .execAndForget }
            .map(\.rawValue)

        XCTAssertEqual(advertisedCommands.count, Set(advertisedCommands).count, "Top-level CLI help contains duplicate commands")
        XCTAssertEqual(Set(advertisedCommands), Set(expectedCommands))
    }
}
