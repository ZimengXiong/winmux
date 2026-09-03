@testable import AppBundle
import AppKit
import Common
import XCTest

struct WorkspaceNamingTestMonitor: Monitor {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

@MainActor
final class WorkspaceNamingTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testSanitizedWorkspaceSidebarHoveredWorkspaceNameClearsDeadWorkspaceReferences() {
        let sanitized = sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: ["live"],
            hoveredWorkspaceName: "dead",
        )

        XCTAssertNil(sanitized)
    }

    func testSanitizedWorkspaceSidebarHoveredWorkspaceNameKeepsLiveHoverState() {
        let sanitized = sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: ["live"],
            hoveredWorkspaceName: "live",
        )

        XCTAssertEqual(sanitized, "live")
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

    func testAutomaticWorkspaceDisplayNamesFollowProjectOrderInsteadOfRawNameSort() {
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 201, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 202, parent: second.rootTilingContainer)

        XCTAssertEqual(
            orderedUserFacingWorkspaces(in: first.projectId, focusedWorkspace: focus.workspace)
                .filter(\.usesAutomaticDisplayName)
                .map(\.name),
            ["10", "2"],
        )
        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 2")
    }

    func testReconcileRepairsMissingProjectWorkspaceIndex() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 211, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 212, parent: second.rootTilingContainer)

        var project = winMuxWorkspaceState.projectsById[first.projectId].orDie()
        project.workspaceOrder = [first.id]
        winMuxWorkspaceState.projectsById[first.projectId] = project

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(
            orderedUserFacingWorkspaces(in: first.projectId, focusedWorkspace: focus.workspace)
                .filter(\.usesAutomaticDisplayName)
                .map(\.name),
            ["1", "2"],
        )
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 2")
    }

    func testNextAutomaticWorkspaceRawNameReusesLowestNumericGap() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 208, parent: first.rootTilingContainer)
        let thirdRaw = Workspace.get(byName: "3")
        thirdRaw.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 209, parent: thirdRaw.rootTilingContainer)

        XCTAssertEqual(nextSidebarCreatedWorkspaceName(), "2")
    }

    func testNextAutomaticWorkspaceRawNameSkipsNamesForcedToAnotherMonitor() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])
        config.workspaceToMonitorForceAssignment["1"] = [.sequenceNumber(2)]

        XCTAssertEqual(nextSidebarCreatedWorkspaceName(monitor: main), "2")
        XCTAssertEqual(nextSidebarCreatedWorkspaceName(monitor: secondary), "1")
    }

    func testAutomaticNumericWorkspaceDisplayNamesCompactWithoutRenamingWorkspaceIds() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 6, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "3")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 7, parent: second.rootTilingContainer)

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(first.name, "1")
        XCTAssertEqual(second.name, "3")
        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 2")
        XCTAssertTrue(Workspace.existing(byName: "3") === second)
    }

    func testDeletingMiddleAutomaticWorkspaceCompactsNamesWithoutReorderingSurvivors() throws {
        let first = Workspace.get(byName: "10")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 203, parent: first.rootTilingContainer)
        let deleted = Workspace.get(byName: "2")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 204, parent: deleted.rootTilingContainer)
        let third = Workspace.get(byName: "7")
        third.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 205, parent: third.rootTilingContainer)

        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertNil(Workspace.existing(byName: deleted.name))
        XCTAssertEqual(
            orderedUserFacingWorkspaces(in: first.projectId, focusedWorkspace: focus.workspace)
                .filter(\.usesAutomaticDisplayName)
                .map(\.name),
            ["10", "7"],
        )
        XCTAssertEqual(workspaceDisplayName(first.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(third.name), "Workspace 2")
    }

    func testWorkspaceNameAfterCompactionUsesCurrentAutomaticName() throws {
        let deleted = Workspace.get(byName: "10")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 206, parent: deleted.rootTilingContainer)
        let survivor = Workspace.get(byName: "2")
        survivor.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 207, parent: survivor.rootTilingContainer)
        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertEqual(survivor.name, "2")
        XCTAssertEqual(workspaceDisplayName(survivor.name), "Workspace 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[survivor.name])
    }

    func testAutomaticWorkspaceDisplayNameCompactionPreservesFocus() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 8, parent: first.rootTilingContainer)
        let focused = Workspace.get(byName: "3")
        focused.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 9, parent: focused.rootTilingContainer)
        _ = focused.focusWorkspace()

        Workspace.reconcileWorkspaceState()

        XCTAssertEqual(focused.name, "3")
        XCTAssertEqual(workspaceDisplayName(focused.name), "Workspace 2")
        XCTAssertTrue(focus.workspace === focused)
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
        XCTAssertEqual(focus.workspace.name, "1")
    }

    func testAutomaticWorkspaceDisplayNamesAreGlobalWithinProjectAcrossDisplays() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([main, secondary])

        let mainWorkspace = Workspace.get(byName: "1")
        mainWorkspace.markAsAutomaticallyNamed()
        mainWorkspace.seedMonitorIfNeeded(main)
        _ = TestWindow.new(id: 10, parent: mainWorkspace.rootTilingContainer)
        let secondaryWorkspace = Workspace.get(byName: "2")
        secondaryWorkspace.markAsAutomaticallyNamed()
        secondaryWorkspace.seedMonitorIfNeeded(secondary)
        _ = TestWindow.new(id: 11, parent: secondaryWorkspace.rootTilingContainer)

        XCTAssertEqual(workspaceDisplayName(mainWorkspace.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(secondaryWorkspace.name), "Workspace 2")
        XCTAssertEqual(mainWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertEqual(secondaryWorkspace.projectId, workspaceProjectDefaultId)
    }

    func testProjectsOwnSeparateWorkspaceSetsOnTheSameDisplay() {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 12, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.get(byName: nextSidebarCreatedWorkspaceName(projectId: project.id, monitor: mainMonitor))
        projectWorkspace.markAsAutomaticallyNamed()
        projectWorkspace.assignProject(project.id)
        projectWorkspace.seedMonitorIfNeeded(mainMonitor)
        _ = TestWindow.new(id: 13, parent: projectWorkspace.rootTilingContainer)

        XCTAssertNotEqual(defaultWorkspace.projectId, projectWorkspace.projectId)
        XCTAssertEqual(workspaceDisplayName(defaultWorkspace.name), "Workspace 1")
        XCTAssertEqual(workspaceDisplayName(projectWorkspace.name), "Workspace 1")
    }

    func testWorkspaceSidebarRenameUsesDisplayLabelWithoutRenamingWorkspaceIdentity() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 14, parent: workspace.rootTilingContainer)

        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Code")
        XCTAssertEqual(config.workspaceSidebar.workspaceLabels[workspace.name], "Code")
        XCTAssertTrue(Workspace.existing(byName: "1") === workspace)
        XCTAssertNil(Workspace.existing(byName: "Code"))
    }

    func testResettingWorkspaceNameFromSidebarUsesDefaultDisplayName() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 114, parent: workspace.rootTilingContainer)
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        try resetWorkspaceSidebarName(workspaceName: workspace.name)

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Workspace 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[workspace.name])
    }

    func testRenamingWorkspaceToDefaultDisplayNameClearsLabel() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 214, parent: workspace.rootTilingContainer)
        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Workspace 1")

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Workspace 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[workspace.name])
    }

    func testWorkspaceRenameRejectsEmptyDisplayName() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()

        XCTAssertThrowsError(try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "  "))
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[workspace.name])
    }

    func testDeletingWorkspaceKeepsStableWorkspaceIdsAndCompactsDisplayNames() throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let firstWindow = TestWindow.new(id: 15, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 16, parent: second.rootTilingContainer)
        try renameWorkspaceForSidebar(workspaceName: first.name, displayName: "Code")

        try deleteWorkspaceForSidebar(workspaceName: first.name)

        XCTAssertNil(Workspace.existing(byName: "1"))
        XCTAssertTrue(Workspace.existing(byName: "2") === second)
        XCTAssertTrue(firstWindow.nodeWorkspace === second)
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 1")
        XCTAssertNil(config.workspaceSidebar.workspaceLabels[first.name])
    }

    func testDeletingFocusedWorkspaceFocusesNextClosestWorkspace() throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 115, parent: first.rootTilingContainer)
        let deleted = Workspace.get(byName: "2")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 116, parent: deleted.rootTilingContainer)
        let next = Workspace.get(byName: "3")
        next.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 117, parent: next.rootTilingContainer)
        _ = deleted.focusWorkspace()

        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertTrue(focus.workspace === next)
        XCTAssertTrue(Workspace.existing(byName: "3") === next)
    }

    func testDeletingLastFocusedWorkspaceFocusesPreviousClosestWorkspace() throws {
        let previous = Workspace.get(byName: "1")
        previous.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 118, parent: previous.rootTilingContainer)
        let deleted = Workspace.get(byName: "2")
        deleted.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 119, parent: deleted.rootTilingContainer)
        _ = deleted.focusWorkspace()

        try deleteWorkspaceForSidebar(workspaceName: deleted.name)

        XCTAssertTrue(focus.workspace === previous)
        XCTAssertTrue(Workspace.existing(byName: "1") === previous)
    }

    func testRenamingAndDeletingProjectKeepsFallbackWorkspaces() throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 17, parent: defaultWorkspace.rootTilingContainer)
        _ = defaultWorkspace.focusWorkspace()
        Workspace.reconcileWorkspaceState()
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.get(byName: "2")
        projectWorkspace.markAsAutomaticallyNamed()
        projectWorkspace.assignProject(project.id)
        projectWorkspace.seedMonitorIfNeeded(mainMonitor)
        let projectWindow = TestWindow.new(id: 18, parent: projectWorkspace.rootTilingContainer)

        try renameWorkspaceProject(project.id, displayName: "Work")
        try deleteWorkspaceProject(project.id)

        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
        XCTAssertNil(Workspace.existing(byName: projectWorkspace.name))
        XCTAssertTrue(projectWindow.nodeWorkspace === defaultWorkspace)
        XCTAssertEqual(defaultWorkspace.projectId, workspaceProjectDefaultId)
    }

    func testClosingProjectWindowsDeletesProjectWithoutMovingWindowsToFallback() async throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 217, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = Workspace.get(byName: "2")
        projectWorkspace.markAsAutomaticallyNamed()
        projectWorkspace.assignProject(project.id)
        projectWorkspace.seedMonitorIfNeeded(mainMonitor)
        let projectWindow = TestWindow.new(id: 218, parent: projectWorkspace.rootTilingContainer)
        config.workspaceSidebar.projectDeletionAction = .closeWindows
        config.workspaceSidebar.projectLabels[project.id.rawValue] = "Temporary"
        config.workspaceSidebar.projectColors[project.id.rawValue] = "#60A5FA"

        try await deleteWorkspaceProjectFromSidebar(project.id)

        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
        XCTAssertNil(Workspace.existing(byName: projectWorkspace.name))
        XCTAssertNil(projectWindow.nodeWorkspace)
        XCTAssertFalse(defaultWorkspace.allLeafWindowsRecursive.contains(projectWindow))
        XCTAssertNil(config.workspaceSidebar.projectLabels[project.id.rawValue])
        XCTAssertNil(config.workspaceSidebar.projectColors[project.id.rawValue])
    }

    func testCreatedProjectPersistsIdentityAndDeleteRemovesPersistedIdentity() throws {
        let project = createWorkspaceProject()

        XCTAssertEqual(config.workspaceSidebar.projectLabels[project.id.rawValue], project.id.rawValue)
        try renameWorkspaceProject(project.id, displayName: "Work")
        XCTAssertEqual(config.workspaceSidebar.projectLabels[project.id.rawValue], "Work")
        config.workspaceSidebar.projectColors[project.id.rawValue] = "#60A5FA"
        try deleteWorkspaceProject(project.id)

        XCTAssertNil(config.workspaceSidebar.projectLabels[project.id.rawValue])
        XCTAssertNil(config.workspaceSidebar.projectColors[project.id.rawValue])
        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
        XCTAssertNil(winMuxWorkspaceState.projectsById[WorkspaceProjectId("Work")])
    }

    func testPersistedProjectLabelMaterializesProject() {
        config.workspaceSidebar.projectLabels["project-7"] = "Research"

        let project = workspaceProjects().first { $0.id == "project-7" }

        XCTAssertEqual(project?.name, "Research")
        XCTAssertTrue(canDeleteWorkspaceProject("project-7"))
    }

    func testPersistedProjectMaterializesWithEmptyWorkspace() {
        let originalFocus = focus.workspace
        let projectId = WorkspaceProjectId("project-empty")
        config.workspaceSidebar.projectLabels[projectId.rawValue] = "Empty Project"

        _ = workspaceProjects()

        let projectWorkspaces = Workspace.all.filter { $0.projectId == projectId }
        XCTAssertEqual(projectWorkspaces.count, 1)
        XCTAssertTrue(projectWorkspaces[0].isEffectivelyEmpty)
        XCTAssertEqual(focus.workspace, originalFocus)
    }

    func testCreatedProjectStartsWithEmptyWorkspace() {
        let originalFocus = focus.workspace

        let project = createWorkspaceProject()

        let projectWorkspaces = Workspace.all.filter { $0.projectId == project.id }
        XCTAssertEqual(projectWorkspaces.count, 1)
        XCTAssertTrue(projectWorkspaces[0].isEffectivelyEmpty)
        XCTAssertEqual(focus.workspace, originalFocus)
    }

    func testProjectCreationUsesUniqueIds() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()

        assertUuidProjectId(first.id)
        assertUuidProjectId(second.id)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(
            Set(workspaceProjects().map(\.id).filter { $0.hasPrefix("project-") }),
            Set([first.id, second.id]),
        )
    }

    func testProjectCreationAppendsAfterDeletedMiddleProject() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()
        let third = createWorkspaceProject()

        try deleteWorkspaceProject(second.id)
        let fourth = createWorkspaceProject()

        assertUuidProjectId(first.id)
        assertUuidProjectId(second.id)
        assertUuidProjectId(third.id)
        assertUuidProjectId(fourth.id)
        XCTAssertEqual(Set([first.id, second.id, third.id, fourth.id]).count, 4)
        XCTAssertEqual(
            workspaceProjects().map(\.id).filter { $0.hasPrefix("project-") },
            [first.id, third.id, fourth.id],
        )
    }

    func testProjectIdsDoNotRepeatAcrossWorkspaceStateRestart() {
        var beforeRestart = WinMuxWorkspaceState()
        let retiredId = beforeRestart.nextGeneratedProjectIdentity().id
        beforeRestart.registerProject(WorkspaceProject(id: retiredId, name: "Retired", order: 1))

        let afterRestart = WinMuxWorkspaceState()
        let newId = afterRestart.nextGeneratedProjectIdentity().id

        assertUuidProjectId(retiredId)
        assertUuidProjectId(newId)
        XCTAssertNotEqual(newId, retiredId)
    }

    func testProjectNamesFollowStableInsertionOrder() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()
        let third = createWorkspaceProject()

        XCTAssertEqual(
            workspaceProjects().map(\.id).filter { $0.hasPrefix("project-") },
            [first.id, second.id, third.id],
        )
        XCTAssertEqual(
            workspaceProjects().filter { $0.id.hasPrefix("project-") }.map(\.name),
            ["Project 1", "Project 2", "Project 3"],
        )
    }

    func testDeletingProjectFallsBackToClosestProject() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()

        XCTAssertEqual(workspaceProjectFallbackForDeletion(excluding: first.id), second.id)
        XCTAssertEqual(workspaceProjectFallbackForDeletion(excluding: second.id), first.id)
    }

    func testDeletingActiveProjectSwitchesToClosestProject() throws {
        let first = createWorkspaceProject()
        let second = createWorkspaceProject()
        XCTAssertNotNil(switchWorkspaceProject(first.id, on: mainMonitor))

        try deleteWorkspaceProject(first.id)

        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), second.id)
        XCTAssertFalse(workspaceProjects().contains { $0.id == first.id })
    }

    func testSameProjectCanStayActiveOnMultipleDisplays() {
        let main = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Left",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        let secondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Main",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        setMonitorsForTests([main, secondary])
        let project = createWorkspaceProject()

        let mainWorkspace = switchWorkspaceProject(project.id, on: main)
        let secondaryWorkspace = switchWorkspaceProject(project.id, on: secondary)

        XCTAssertNotNil(mainWorkspace)
        XCTAssertNotNil(secondaryWorkspace)
        XCTAssertFalse(mainWorkspace === secondaryWorkspace)
        XCTAssertEqual(activeWorkspaceProjectId(for: main), project.id)
        XCTAssertEqual(activeWorkspaceProjectId(for: secondary), project.id)
        XCTAssertEqual(main.activeWorkspace.projectId, project.id)
        XCTAssertEqual(secondary.activeWorkspace.projectId, project.id)
        XCTAssertFalse(main.activeWorkspace === secondary.activeWorkspace)
    }

    func testProjectSwitchCanReturnToDefaultOnSameMonitor() throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 401, parent: defaultWorkspace.rootTilingContainer)
        XCTAssertTrue(mainMonitor.setActiveWorkspace(defaultWorkspace))
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))

        XCTAssertTrue(mainMonitor.activeWorkspace === projectWorkspace)

        let returnedWorkspace = try XCTUnwrap(switchWorkspaceProject(workspaceProjectDefaultId, on: mainMonitor))

        XCTAssertTrue(mainMonitor.activeWorkspace === returnedWorkspace)
        XCTAssertEqual(returnedWorkspace.projectId, workspaceProjectDefaultId)
        XCTAssertTrue(returnedWorkspace === defaultWorkspace)
    }

    private func assertUuidProjectId(
        _ projectId: WorkspaceProjectId,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let rawId = projectId.rawValue
        XCTAssertTrue(rawId.hasPrefix("project-"), file: file, line: line)
        XCTAssertNotNil(UUID(uuidString: String(rawId.dropFirst("project-".count))), file: file, line: line)
    }

}
