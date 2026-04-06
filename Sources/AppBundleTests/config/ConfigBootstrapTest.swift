@testable import AppBundle
import XCTest

@MainActor
final class ConfigBootstrapTest: XCTestCase {
    func testStarterConfigParses() {
        let (parsedConfig, errors) = parseConfig(starterConfigText())
        assertEquals(errors, [])

        let bindings: [(String, String)] = parsedConfig.modes["main"]?.bindings.values.map {
            ($0.descriptionWithKeyNotation, $0.commands.prettyDescription)
        } ?? []
        let bindingMap: [String: String] = Dictionary(uniqueKeysWithValues: bindings)

        XCTAssertEqual(bindingMap["alt-space"], "layout horizontal vertical")
        XCTAssertEqual(bindingMap["alt-h"], "focus left")
        XCTAssertEqual(bindingMap["alt-shift-h"], "move left")
        XCTAssertEqual(bindingMap["cmd-shift-h"], "join-with left")
        XCTAssertEqual(bindingMap["ctrl-1"], "workspace 1")
        XCTAssertEqual(bindingMap["alt-shift-1"], "move-node-to-workspace 1")
        XCTAssertEqual(bindingMap["alt-shift-t"], "layout floating tiling")
        XCTAssertEqual(bindingMap["alt-shift-m"], "fullscreen")
        XCTAssertNil(bindingMap["alt-slash"])
        XCTAssertNil(bindingMap["alt-comma"])
    }
}
