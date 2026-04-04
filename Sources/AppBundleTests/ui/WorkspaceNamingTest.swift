@testable import AppBundle
import XCTest

@MainActor
final class WorkspaceNamingTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSanitizedWorkspaceSidebarTransientStateClearsDeadWorkspaceReferences() {
        let sanitized = sanitizedWorkspaceSidebarTransientState(
            visibleWorkspaceNames: ["live"],
            state: WorkspaceSidebarTransientState(
                hoveredWorkspaceName: "dead",
            ),
        )

        XCTAssertNil(sanitized.hoveredWorkspaceName)
    }

    func testSanitizedWorkspaceSidebarTransientStateKeepsLiveHoverState() {
        let sanitized = sanitizedWorkspaceSidebarTransientState(
            visibleWorkspaceNames: ["live"],
            state: WorkspaceSidebarTransientState(
                hoveredWorkspaceName: "live",
            ),
        )

        XCTAssertEqual(sanitized.hoveredWorkspaceName, "live")
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

    func testAutomaticNumericWorkspaceDisplayNamesCompactLiveWorkspaceSet() {
        let first = Workspace.get(byName: "3")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 1, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "7")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 2, parent: second.rootTilingContainer)

        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 2")
    }

    func testAutomaticDraftWorkspaceDisplayNamesCompactLiveWorkspaceSet() {
        let first = Workspace.get(byName: "__sidebar_draft_workspace_1")
        first.markAsSidebarManaged()
        _ = TestWindow.new(id: 3, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "__sidebar_draft_workspace_3")
        second.markAsSidebarManaged()
        _ = TestWindow.new(id: 4, parent: second.rootTilingContainer)

        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 2")
    }

    func testSidebarWorkspaceCreationUsesAutomaticWorkspaceName() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let window = TestWindow.new(id: 5, parent: first.rootTilingContainer)
        _ = first.focusWorkspace()

        XCTAssertTrue(createWorkspaceFromSidebarDrag(sourceNode: window, sourceWindow: window))
        XCTAssertNotNil(Workspace.existing(byName: "2"))
        XCTAssertNil(Workspace.existing(byName: "__sidebar_draft_workspace_1"))
        XCTAssertEqual(focus.workspace.name, "2")
    }
}
