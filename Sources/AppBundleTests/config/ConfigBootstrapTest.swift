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
        XCTAssertTrue(parsedConfig.windowTabs.enabled)
        XCTAssertEqual(parsedConfig.windowTabs.height, 36)
        XCTAssertTrue(parsedConfig.workspaceSidebar.enabled)
        XCTAssertEqual(parsedConfig.workspaceSidebar.width, 240)
        XCTAssertTrue(parsedConfig.enableWindowManagement)
        XCTAssertTrue(parsedConfig.autoReloadConfig)
        if case .constant(let horizontalGap) = parsedConfig.gaps.inner.horizontal {
            XCTAssertEqual(horizontalGap, 8)
        } else {
            XCTFail("Expected constant horizontal gap")
        }
        if case .constant(let verticalGap) = parsedConfig.gaps.inner.vertical {
            XCTAssertEqual(verticalGap, 8)
        } else {
            XCTFail("Expected constant vertical gap")
        }
        if case .constant(let outerLeftGap) = parsedConfig.gaps.outer.left {
            XCTAssertEqual(outerLeftGap, 8)
        } else {
            XCTFail("Expected constant outer left gap")
        }
        XCTAssertEqual(parsedConfig.configVersion, 2)
    }

    func testEnsureBootstrapConfigCopiesLegacyConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
            .appending(path: "WinMuxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    func testEnsureBootstrapConfigImportsAerospaceConfigWhenNoWinMuxConfigExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let aerospaceUrl = tempDir.appending(path: "aerospace.toml")
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let aerospaceText = """
            start-at-login = false
            default-root-container-layout = 'accordion'
            accordion-padding = 22
            exec-on-workspace-change = ['/bin/sh', '-c', 'echo $AEROSPACE_FOCUSED_WORKSPACE $AEROSPACE_PREV_WORKSPACE $AEROSPACE_WORKSPACE']

            [mode.main.binding]
            alt-h = 'layout accordion tiles'
            alt-j = 'layout h_accordion v_accordion'
            alt-l = 'focus --window-id $AEROSPACE_WINDOW_ID'
            """
        try aerospaceText.write(to: aerospaceUrl, atomically: true, encoding: .utf8)

        let didMaterialize = try materializeBootstrapConfigIfNeeded(
            targetUrl: targetUrl,
            existingLegacyUrls: [],
            aerospaceImportUrl: aerospaceUrl,
        )

        XCTAssertTrue(didMaterialize)
        let migratedText = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertTrue(migratedText.contains("# Migrated from AeroSpace config by WinMux."))
        XCTAssertTrue(migratedText.contains("default-root-container-layout = 'tab-group'"))
        XCTAssertTrue(migratedText.contains("tab-group-padding = 22"))
        XCTAssertTrue(migratedText.contains("layout tab-group tiles"))
        XCTAssertTrue(migratedText.contains("layout h_tab_group v_tab_group"))
        XCTAssertTrue(migratedText.contains("$WINMUX_FOCUSED_WORKSPACE $WINMUX_PREV_WORKSPACE $WINMUX_WORKSPACE"))
        XCTAssertTrue(migratedText.contains("$WINMUX_WINDOW_ID"))
        XCTAssertFalse(migratedText.contains("accordion"))
        XCTAssertFalse(migratedText.contains("AEROSPACE_"))
    }
}
