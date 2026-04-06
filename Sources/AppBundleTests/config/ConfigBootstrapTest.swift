@testable import AppBundle
import Foundation
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

    func testEnsureBootstrapConfigCopiesLegacyConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "AeroSpaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let legacyUrl = tempDir.appending(path: "legacy.toml")
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let legacyText = """
            config-version = 2

            [mode.main.binding]
            alt-h = 'focus left'
            """
        try legacyText.write(to: legacyUrl, atomically: true, encoding: .utf8)

        let didMaterialize = try materializeBootstrapConfigIfNeeded(
            targetUrl: targetUrl,
            existingLegacyUrls: [legacyUrl],
        )

        XCTAssertTrue(didMaterialize)
        let copiedText = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertEqual(copiedText, legacyText)
    }

    func testEnsureBootstrapConfigPrefersFirstLegacyConfigWithoutFailing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "AeroSpaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let preferredLegacyUrl = tempDir.appending(path: "preferred.toml")
        let secondaryLegacyUrl = tempDir.appending(path: "secondary.toml")
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let preferredText = """
            config-version = 2

            [mode.main.binding]
            alt-h = 'focus left'
            """
        let secondaryText = """
            config-version = 2

            [mode.main.binding]
            alt-l = 'focus right'
            """
        try preferredText.write(to: preferredLegacyUrl, atomically: true, encoding: .utf8)
        try secondaryText.write(to: secondaryLegacyUrl, atomically: true, encoding: .utf8)

        let didMaterialize = try materializeBootstrapConfigIfNeeded(
            targetUrl: targetUrl,
            existingLegacyUrls: [preferredLegacyUrl, secondaryLegacyUrl],
        )

        XCTAssertTrue(didMaterialize)
        let copiedText = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertEqual(copiedText, preferredText)
    }
}
