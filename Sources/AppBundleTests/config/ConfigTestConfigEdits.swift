@testable import AppBundle
import AppKit
import Common
import XCTest

extension ConfigTest {
    func testUpdateWorkspaceSidebarLabelConfigAddsSectionWhenMissing() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
            workspaceName: "1",
            label: "Code",
        )

        XCTAssertTrue(updated.contains("[workspace-sidebar.workspace-labels]"))
        XCTAssertTrue(updated.contains("\"1\" = \"Code\""))
    }

    func testUpdateWorkspaceSidebarLabelConfigReplacesExistingLabel() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Old"
            "2" = "Web"
            """,
            workspaceName: "1",
            label: "Code",
        )

        XCTAssertTrue(updated.contains("\"1\" = \"Code\""))
        XCTAssertFalse(updated.contains("\"1\" = \"Old\""))
        XCTAssertTrue(updated.contains("\"2\" = \"Web\""))
    }

    func testUpdateWorkspaceSidebarLabelConfigAddsNewLabelWithoutExtraBlankLine() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Code"
            """,
            workspaceName: "2",
            label: "Web",
        )

        XCTAssertEqual(
            updated,
            """
            [workspace-sidebar.workspace-labels]
            "1" = "Code"
            "2" = "Web"
            """,
        )
    }

    func testUpdateWorkspaceSidebarLabelConfigRemovesLastLabelSection() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Code"

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            workspaceName: "1",
            label: nil,
        )

        XCTAssertFalse(updated.contains("[workspace-sidebar.workspace-labels]"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigAddsAndReplacesColor() {
        let added = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [workspace-sidebar]
                enabled = true
            """,
            projectId: "project-1",
            colorHex: "#60A5FA",
        )

        XCTAssertTrue(added.contains("[workspace-sidebar.project-colors]"))
        XCTAssertTrue(added.contains("\"project-1\" = \"#60A5FA\""))

        let replaced = updateWorkspaceSidebarProjectColorConfig(
            in: added,
            projectId: "project-1",
            colorHex: "#F87171",
        )

        XCTAssertTrue(replaced.contains("\"project-1\" = \"#F87171\""))
        XCTAssertFalse(replaced.contains("\"project-1\" = \"#60A5FA\""))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigRemovesLastColorSection() {
        let updated = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [workspace-sidebar.project-colors]
            "project-1" = "#60A5FA"

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            projectId: "project-1",
            colorHex: nil,
        )

        XCTAssertFalse(updated.contains("[workspace-sidebar.project-colors]"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarMenuBarReserveConfigAddsValueToExistingSection() {
        let updated = updateWorkspaceSidebarMenuBarReserveConfig(
            in: """
            [workspace-sidebar]
                enabled = true
                width = 240

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            height: 32,
        )

        XCTAssertTrue(updated.contains("[workspace-sidebar]\n    menu-bar-reserve-height = 32\n    enabled = true"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarMenuBarReserveConfigReplacesValueAndPreservesComment() {
        let updated = updateWorkspaceSidebarMenuBarReserveConfig(
            in: """
            [workspace-sidebar]
                menu-bar-reserve-height = 28 # visible menu bar
                enabled = true
            """,
            height: 0,
        )

        XCTAssertTrue(updated.contains("menu-bar-reserve-height = 0 # visible menu bar"))
        XCTAssertFalse(updated.contains("menu-bar-reserve-height = 28"))
    }

    func testUpdateWorkspaceSidebarProjectDeletionActionReplacesValueAndPreservesComment() {
        let updated = updateWorkspaceSidebarProjectDeletionActionConfig(
            in: """
            [workspace-sidebar]
                project-deletion-action = 'move-windows-to-fallback' # legacy
                enabled = true
            """,
            action: .closeWindows,
        )

        XCTAssertTrue(updated.contains("project-deletion-action = 'close-windows' # legacy"))
        XCTAssertFalse(updated.contains("move-windows-to-fallback"))
    }

    func testUpdateSettingsScalarConfigReplacesWorkspaceSidebarStayOnTop() {
        let updated = updateSettingsScalarConfig(
            in: """
            [workspace-sidebar]
                enabled = true
                stay-on-top = true

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            section: "workspace-sidebar",
            key: "stay-on-top",
            renderedValue: "false",
        )

        XCTAssertTrue(updated.contains("stay-on-top = false"))
        XCTAssertFalse(updated.contains("stay-on-top = true"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testPersistProjectMetadataCreatesOnlyAtExplicitMissingTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxProjectPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let targetUrl = tempDir.appending(path: "nested/winmux.toml")

        try persistWorkspaceSidebarProjectMetadata(
            projectId: "project-test",
            label: "Research",
            colorHex: "#60A5FA",
            targetUrl: targetUrl,
        )

        let persisted = try String(contentsOf: targetUrl, encoding: .utf8)
        let (parsed, errors) = parseConfig(persisted)
        XCTAssertEqual(errors.descriptions, [])
        XCTAssertEqual(parsed.workspaceSidebar.projectLabels["project-test"], "Research")
        XCTAssertEqual(parsed.workspaceSidebar.projectColors["project-test"], "#60A5FA")
    }

    func testPersistProjectMetadataDoesNotReplaceInvalidUtf8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxProjectPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let invalidUtf8 = Data([0xC3, 0x28])
        try invalidUtf8.write(to: targetUrl)

        XCTAssertThrowsError(
            try persistWorkspaceSidebarProjectMetadata(
                projectId: "project-test",
                label: "Must Not Be Written",
                colorHex: nil,
                targetUrl: targetUrl,
            ),
        )
        XCTAssertEqual(try Data(contentsOf: targetUrl), invalidUtf8)
    }

    func testPersistProjectMetadataRemovesLabelAndColorTogetherAndPreservesOtherConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxProjectPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let original = """
            config-version = 2

            [workspace-sidebar.project-labels]
            "project-test" = "Disposable"
            "project-keep" = "Keep"

            [workspace-sidebar.project-colors]
            "project-test" = "#60A5FA"
            "project-keep" = "#F87171"

            [mode.main.binding]
            alt-h = 'focus left' # preserve me
            """
        try original.write(to: targetUrl, atomically: true, encoding: .utf8)

        try persistWorkspaceSidebarProjectMetadata(
            projectId: "project-test",
            label: nil,
            colorHex: nil,
            targetUrl: targetUrl,
        )

        let persisted = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertFalse(persisted.contains("\"project-test\""))
        XCTAssertTrue(persisted.contains("\"project-keep\" = \"Keep\""))
        XCTAssertTrue(persisted.contains("\"project-keep\" = \"#F87171\""))
        XCTAssertTrue(persisted.contains("alt-h = 'focus left' # preserve me"))
        let (parsed, errors) = parseConfig(persisted)
        XCTAssertEqual(errors.descriptions, [])
        XCTAssertNil(parsed.workspaceSidebar.projectLabels["project-test"])
        XCTAssertNil(parsed.workspaceSidebar.projectColors["project-test"])
    }

    func testTomlEscapeEncodesEveryControlCharacter() {
        let controlScalars = (Array(0x00 ... 0x1F) + Array(0x7F ... 0x9F))
            .compactMap(UnicodeScalar.init)
        let raw = String(String.UnicodeScalarView(controlScalars))
        let escaped = tomlEscape(raw)

        XCTAssertEqual(escaped, "\\u0000\\u0001\\u0002\\u0003\\u0004\\u0005\\u0006\\u0007\\b\\t\\n\\u000B\\f\\r\\u000E\\u000F\\u0010\\u0011\\u0012\\u0013\\u0014\\u0015\\u0016\\u0017\\u0018\\u0019\\u001A\\u001B\\u001C\\u001D\\u001E\\u001F\\u007F\\u0080\\u0081\\u0082\\u0083\\u0084\\u0085\\u0086\\u0087\\u0088\\u0089\\u008A\\u008B\\u008C\\u008D\\u008E\\u008F\\u0090\\u0091\\u0092\\u0093\\u0094\\u0095\\u0096\\u0097\\u0098\\u0099\\u009A\\u009B\\u009C\\u009D\\u009E\\u009F")
        XCTAssertFalse(escaped.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || (0x7F ... 0x9F).contains(scalar.value)
        })
    }

    func testTomlEscapeRoundTripsQuotesBackslashesAndCommentCharacters() {
        let raw = "Client \\\"A\\\" \\\\ # ="
        let updated = updateWorkspaceSidebarProjectLabelConfig(
            in: "config-version = 2",
            projectId: "project-safe",
            label: raw,
        )
        let (parsed, errors) = parseConfig(updated)
        XCTAssertEqual(errors.descriptions, [])
        XCTAssertEqual(parsed.workspaceSidebar.projectLabels["project-safe"], raw)
    }

}
