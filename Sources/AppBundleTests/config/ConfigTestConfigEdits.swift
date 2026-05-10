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

    func testUpdateWindowManagementConfigReplacesExistingValueAndPreservesComment() {
        let updated = updateWindowManagementConfig(
            in: """
            start-at-login = false
            enable-window-management = true # keep this comment

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            enabled: false,
        )

        XCTAssertTrue(updated.contains("enable-window-management = false # keep this comment"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
        XCTAssertTrue(updated.contains("alt-h = 'focus left'"))
        XCTAssertFalse(updated.contains("enable-window-management = true # keep this comment"))
    }

    func testUpdateWindowManagementConfigAppendsWithoutTouchingBindings() {
        let updated = updateWindowManagementConfig(
            in: """
            [mode.main.binding]
                alt-h = 'focus left'
                ctrl-alt-left = 'focus monitor left'
            """,
            enabled: false,
        )

        XCTAssertTrue(updated.contains("[mode.main.binding]"))
        XCTAssertTrue(updated.contains("alt-h = 'focus left'"))
        XCTAssertTrue(updated.contains("ctrl-alt-left = 'focus monitor left'"))
        XCTAssertTrue(updated.contains("enable-window-management = false"))
    }

    func testUpdateWindowManagementConfigAppendsAtTopLevelBeforeBindingTapSection() {
        let updated = updateWindowManagementConfig(
            in: """
            [mode.main.binding-tap]
                left-alt = 'focus left'
            """,
            enabled: false,
        )

        XCTAssertEqual(
            updated,
            """
            enable-window-management = false

            [mode.main.binding-tap]
                left-alt = 'focus left'
            """,
        )
        let (parsed, errors) = parseConfig(updated)
        assertEquals(errors, [])
        XCTAssertFalse(parsed.enableWindowManagement)
        XCTAssertEqual(parsed.modes[mainModeId]?.tapBindings["left-alt"]?.descriptionWithKeyNotation, "left-alt")
    }

    func testUpdateWindowManagementConfigRepairsMisplacedLineInsideBindingTapSection() {
        let updated = updateWindowManagementConfig(
            in: """
            [mode.main.binding-tap]
                left-alt = 'focus left'
            enable-window-management = true # legacy misplaced line
            """,
            enabled: false,
        )

        XCTAssertEqual(
            updated,
            """
            enable-window-management = false # legacy misplaced line

            [mode.main.binding-tap]
                left-alt = 'focus left'
            """,
        )
        let (parsed, errors) = parseConfig(updated)
        assertEquals(errors, [])
        XCTAssertFalse(parsed.enableWindowManagement)
        XCTAssertEqual(parsed.modes[mainModeId]?.tapBindings["left-alt"]?.descriptionWithKeyNotation, "left-alt")
    }
}
