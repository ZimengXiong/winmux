@testable import AppBundle
import XCTest

final class ShortcutSettingsConfigEditsTest: XCTestCase {
    func testUpdateModeBindingConfigAddsMissingSection() {
        let updated = updateModeBindingConfig(
            in: """
            start-at-login = true
            """,
            modeName: "main",
            tableKey: "binding",
            managedCommands: ["focus left"],
            assignments: ["alt-h": "focus left"]
        )

        XCTAssertTrue(updated.contains("[mode.main.binding]"))
        XCTAssertTrue(updated.contains("alt-h = \"focus left\""))
    }

    func testUpdateModeBindingConfigReplacesManagedBindingsAndPreservesCustomOnes() {
        let updated = updateModeBindingConfig(
            in: """
            [mode.main.binding]
            alt-h = "focus left"
            alt-l = "focus right"
            cmd-shift-x = "exec-and-forget open -a Xcode"
            """,
            modeName: "main",
            tableKey: "binding",
            managedCommands: ["focus left", "focus right"],
            assignments: ["alt-left": "focus left"]
        )

        XCTAssertTrue(updated.contains("alt-left = \"focus left\""))
        XCTAssertFalse(updated.contains("alt-h = \"focus left\""))
        XCTAssertFalse(updated.contains("alt-l = \"focus right\""))
        XCTAssertTrue(updated.contains("cmd-shift-x = \"exec-and-forget open -a Xcode\""))
    }

    func testReadModeBindingEntriesReadsSimpleScalarBindings() {
        let entries = readModeBindingEntries(
            in: """
            [mode.main.binding]
            alt-h = "focus left"
            "cmd-shift-/" = "reload-config"
            """,
            modeName: "main",
            tableKey: "binding"
        )

        XCTAssertEqual(entries["alt-h"], "focus left")
        XCTAssertEqual(entries["cmd-shift-/"], "reload-config")
    }

    func testInferWorkspaceShortcutStatePrefersPatternAndExtractsOverrides() {
        let state = inferWorkspaceShortcutState(
            from: [
                "alt-1": "workspace 1",
                "alt-2": "workspace 2",
                "cmd-3": "workspace 3",
                "alt-shift-1": "move-node-to-workspace 1",
                "alt-shift-2": "move-node-to-workspace 2",
                "cmd-shift-3": "move-node-to-workspace 3",
            ],
            workspaceNumbers: ["1", "2", "3"]
        )

        XCTAssertEqual(state.switchModifiers, [.option])
        XCTAssertEqual(state.moveModifiers, [.option, .shift])
        XCTAssertEqual(state.switchOverrides, ["3": "cmd-3"])
        XCTAssertEqual(state.moveOverrides, ["3": "cmd-shift-3"])
    }
}
