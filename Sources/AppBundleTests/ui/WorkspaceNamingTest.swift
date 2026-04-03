@testable import AppBundle
import XCTest

final class WorkspaceNamingTest: XCTestCase {
    func testSanitizedWorkspaceSidebarTransientStateClearsDeadWorkspaceReferences() {
        let sanitized = sanitizedWorkspaceSidebarTransientState(
            visibleWorkspaceNames: ["live"],
            state: WorkspaceSidebarTransientState(
                hoveredWorkspaceName: "dead",
                editingWorkspaceName: "dead",
                editingText: "Old Name",
            ),
        )

        XCTAssertNil(sanitized.hoveredWorkspaceName)
        XCTAssertNil(sanitized.editingWorkspaceName)
        XCTAssertEqual(sanitized.editingText, "")
    }

    func testSanitizedWorkspaceSidebarTransientStateKeepsLiveEditorState() {
        let sanitized = sanitizedWorkspaceSidebarTransientState(
            visibleWorkspaceNames: ["live"],
            state: WorkspaceSidebarTransientState(
                hoveredWorkspaceName: "live",
                editingWorkspaceName: "live",
                editingText: "Current Name",
            ),
        )

        XCTAssertEqual(sanitized.hoveredWorkspaceName, "live")
        XCTAssertEqual(sanitized.editingWorkspaceName, "live")
        XCTAssertEqual(sanitized.editingText, "Current Name")
    }

    func testTrayItemDisablesRawWorkspaceIconWhenDisplayNameIsCustom() {
        let renamedWorkspace = TrayItem(
            type: .workspace,
            name: "1",
            displayName: "Code",
            isActive: true,
            hasFullscreenWindows: false,
        )
        let plainWorkspace = TrayItem(
            type: .workspace,
            name: "1",
            displayName: "1",
            isActive: true,
            hasFullscreenWindows: false,
        )

        XCTAssertNil(renamedWorkspace.systemImageName)
        XCTAssertEqual(plainWorkspace.systemImageName, "1.square.fill")
    }
}
