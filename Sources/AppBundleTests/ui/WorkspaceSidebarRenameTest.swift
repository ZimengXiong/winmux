@testable import AppBundle
import AppKit
import XCTest

final class WorkspaceSidebarRenameTest: XCTestCase {
    func testTypingRenameRequiresSidebarPanelToBeKeyWindow() {
        XCTAssertFalse(
            canStartWorkspaceSidebarTypingRename(
                isAppEnabled: true,
                isSidebarEnabled: true,
                isSidebarVisible: true,
                isSidebarExpanded: true,
                isPanelKeyWindow: false,
                editingWorkspaceName: nil,
                hoveredWorkspaceName: "1",
            ),
        )
        XCTAssertTrue(
            canStartWorkspaceSidebarTypingRename(
                isAppEnabled: true,
                isSidebarEnabled: true,
                isSidebarVisible: true,
                isSidebarExpanded: true,
                isPanelKeyWindow: true,
                editingWorkspaceName: nil,
                hoveredWorkspaceName: "1",
            ),
        )
    }

    func testTypingRenameDoesNotStartWhileAlreadyEditing() {
        XCTAssertFalse(
            canStartWorkspaceSidebarTypingRename(
                isAppEnabled: true,
                isSidebarEnabled: true,
                isSidebarVisible: true,
                isSidebarExpanded: true,
                isPanelKeyWindow: true,
                editingWorkspaceName: "1",
                hoveredWorkspaceName: "1",
            ),
        )
    }

    func testSidebarExpansionLocksWhileEditorIsActive() {
        XCTAssertTrue(
            shouldLockWorkspaceSidebarExpansion(
                hasDropPreview: false,
                hasPinnedDraggedWindow: false,
                isSidebarDragInProgress: false,
                hasActiveEditor: true,
            ),
        )
    }

    func testBeginEditingPlanCommitsPreviousWorkspaceBeforeSwitchingTargets() {
        XCTAssertEqual(
            planWorkspaceSidebarBeginEditing(
                currentEditingWorkspaceName: "a",
                currentEditingText: "Draft A",
                targetWorkspaceName: "b",
                targetInitialText: nil,
                targetPersistedLabel: "Label B",
            ),
            WorkspaceSidebarBeginEditingPlan(
                workspaceToCommit: "a",
                nextEditingWorkspaceName: "b",
                nextEditingText: "Label B",
            ),
        )
    }

    func testBeginEditingPlanPreservesDraftWhenTargetWorkspaceAlreadyEditing() {
        XCTAssertEqual(
            planWorkspaceSidebarBeginEditing(
                currentEditingWorkspaceName: "a",
                currentEditingText: "Draft A",
                targetWorkspaceName: "a",
                targetInitialText: "Seed",
                targetPersistedLabel: "Label A",
            ),
            WorkspaceSidebarBeginEditingPlan(
                workspaceToCommit: nil,
                nextEditingWorkspaceName: "a",
                nextEditingText: "Draft A",
            ),
        )
    }

    func testEditingTextIgnoresStaleFieldUpdatesFromDifferentWorkspace() {
        XCTAssertEqual(
            nextWorkspaceSidebarEditingText(
                currentEditingWorkspaceName: "b",
                fieldWorkspaceName: "a",
                currentEditingText: "Draft B",
                newText: "Stale A",
            ),
            "Draft B",
        )
    }

    func testEditingTextAcceptsUpdatesFromCurrentWorkspaceField() {
        XCTAssertEqual(
            nextWorkspaceSidebarEditingText(
                currentEditingWorkspaceName: "a",
                fieldWorkspaceName: "a",
                currentEditingText: "Draft A",
                newText: "Updated A",
            ),
            "Updated A",
        )
    }

    func testEditorEndEditingActionTreatsCancelMovementAsCancel() {
        XCTAssertEqual(
            workspaceSidebarEditorEndEditingAction(textMovement: NSTextMovement.cancel.rawValue),
            .cancel,
        )
        XCTAssertEqual(
            workspaceSidebarEditorEndEditingAction(textMovement: nil),
            .commit,
        )
    }

    @MainActor
    func testCommittedLabelClearsWhenItMatchesWorkspaceName() {
        XCTAssertNil(normalizedWorkspaceSidebarCommittedLabel(
            workspaceName: "1",
            editingText: " 1 ",
        ))
        XCTAssertEqual(workspaceDefaultDisplayName("1"), "1")
    }

    @MainActor
    func testCommittedLabelClearsWhenItMatchesDraftWorkspaceDefaultName() {
        XCTAssertNil(normalizedWorkspaceSidebarCommittedLabel(
            workspaceName: "__sidebar_draft_workspace_7",
            editingText: "Workspace 7",
        ))
        XCTAssertEqual(workspaceDefaultDisplayName("__sidebar_draft_workspace_7"), "Workspace 7")
    }

    @MainActor
    func testCommittedLabelKeepsRealCustomRename() {
        XCTAssertEqual(
            normalizedWorkspaceSidebarCommittedLabel(
                workspaceName: "1",
                editingText: "Code",
            ),
            "Code",
        )
    }

    @MainActor
    func testDeferredEndEditingCommitLetsExplicitCancelWin() async {
        var editingWorkspaceName: String? = "a"
        var events: [String] = []

        dispatchWorkspaceSidebarEditorEndEditingAction(
            textMovement: nil,
            onCommit: {
                guard editingWorkspaceName == "a" else { return }
                events.append("commit")
                editingWorkspaceName = nil
            },
            onCancel: {
                guard editingWorkspaceName == "a" else { return }
                events.append("cancel")
                editingWorkspaceName = nil
            },
        )

        if editingWorkspaceName == "a" {
            events.append("cancel")
            editingWorkspaceName = nil
        }

        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        await fulfillment(of: [drained], timeout: 1)

        XCTAssertEqual(events, ["cancel"])
    }
}
