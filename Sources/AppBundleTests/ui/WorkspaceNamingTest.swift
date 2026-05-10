@testable import AppBundle
import AppKit
import XCTest

private struct WorkspaceNamingTestMonitor: Monitor {
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

    func testAutomaticNumericWorkspaceNamesCompactLiveWorkspaceSet() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 6, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "3")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 7, parent: second.rootTilingContainer)

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertEqual(first.name, "1")
        XCTAssertEqual(second.name, "2")
        XCTAssertTrue(Workspace.existing(byName: "2") === second)
        XCTAssertNil(Workspace.existing(byName: "3"))
    }

    func testAutomaticWorkspaceNameCompactionPreservesFocus() {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 8, parent: first.rootTilingContainer)
        let focused = Workspace.get(byName: "3")
        focused.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 9, parent: focused.rootTilingContainer)
        _ = focused.focusWorkspace()

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertEqual(focused.name, "2")
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
        XCTAssertEqual(focus.workspace.name, "2")
    }

    func testAutomaticWorkspaceDisplayNamesAreScopedPerDisplay() {
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
        XCTAssertEqual(workspaceDisplayName(secondaryWorkspace.name), "Workspace 1")
        XCTAssertEqual(mainWorkspace.scope, workspaceScope(projectId: workspaceProjectDefaultId, monitor: main))
        XCTAssertEqual(secondaryWorkspace.scope, workspaceScope(projectId: workspaceProjectDefaultId, monitor: secondary))
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

    func testRenamingWorkspaceFromSidebarUsesDisplayLabel() throws {
        let workspace = Workspace.get(byName: "1")
        workspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 14, parent: workspace.rootTilingContainer)

        try renameWorkspaceForSidebar(workspaceName: workspace.name, displayName: "Code")

        XCTAssertEqual(workspace.name, "1")
        XCTAssertEqual(workspaceDisplayName(workspace.name), "Code")
        XCTAssertEqual(config.workspaceSidebar.workspaceLabels[workspace.name], "Code")
    }

    func testDeletingWorkspaceCompactsAutomaticWorkspaceNames() throws {
        let first = Workspace.get(byName: "1")
        first.markAsAutomaticallyNamed()
        let firstWindow = TestWindow.new(id: 15, parent: first.rootTilingContainer)
        let second = Workspace.get(byName: "2")
        second.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 16, parent: second.rootTilingContainer)

        try deleteWorkspaceForSidebar(workspaceName: first.name)

        XCTAssertNil(Workspace.existing(byName: "2"))
        XCTAssertTrue(Workspace.existing(byName: "1") === second)
        XCTAssertTrue(firstWindow.nodeWorkspace === second)
        XCTAssertEqual(workspaceDisplayName(second.name), "Workspace 1")
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
        XCTAssertTrue(Workspace.existing(byName: "2") === next)
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

    func testCreatedProjectPersistsNameAndDeleteRemovesPersistedName() throws {
        let project = createWorkspaceProject()

        XCTAssertEqual(config.workspaceSidebar.projectLabels[project.id], "Project 1")
        try renameWorkspaceProject(project.id, displayName: "Work")
        XCTAssertEqual(config.workspaceSidebar.projectLabels[project.id], "Work")
        config.workspaceSidebar.projectColors[project.id] = "#60A5FA"
        try deleteWorkspaceProject(project.id)

        XCTAssertNil(config.workspaceSidebar.projectLabels[project.id])
        XCTAssertNil(config.workspaceSidebar.projectColors[project.id])
        XCTAssertFalse(workspaceProjects().contains { $0.id == project.id })
    }

    func testPersistedProjectLabelMaterializesProject() {
        config.workspaceSidebar.projectLabels["project-7"] = "Research"

        let project = workspaceProjects().first { $0.id == "project-7" }

        XCTAssertEqual(project?.name, "Research")
        XCTAssertTrue(canDeleteWorkspaceProject("project-7"))
    }

    func testProjectCreationUsesUniqueIdsAfterRename() throws {
        let first = createWorkspaceProject()
        try renameWorkspaceProject(first.id, displayName: "Work")
        let second = createWorkspaceProject()

        XCTAssertEqual(first.id, "project-1")
        XCTAssertEqual(second.id, "project-2")
        XCTAssertEqual(workspaceProjects().map(\.id).filter { $0.hasPrefix("project-") }.sorted(), ["project-1", "project-2"])
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
        XCTAssertEqual(main.activeWorkspace.scope, workspaceScope(projectId: project.id, monitor: main))
        XCTAssertEqual(secondary.activeWorkspace.scope, workspaceScope(projectId: project.id, monitor: secondary))
    }

    func testWorkspaceToMonitorForceAssignmentRejectsWrongMonitor() {
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
        config.workspaceToMonitorForceAssignment["forced"] = [.sequenceNumber(2)]
        let workspace = Workspace.get(byName: "forced")

        XCTAssertFalse(main.setActiveWorkspace(workspace))
        XCTAssertTrue(secondary.setActiveWorkspace(workspace))
        XCTAssertTrue(secondary.activeWorkspace === workspace)
    }

    func testGcMonitorsReconcilesChangedMonitorPointsWithSameMonitorCount() {
        let oldMain = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let oldSecondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([oldMain, oldSecondary])
        let workspace = Workspace.get(byName: "visible")
        _ = TestWindow.new(id: 21, parent: workspace.rootTilingContainer)
        XCTAssertTrue(oldMain.setActiveWorkspace(workspace))

        let newMain = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 1,
            name: "Main",
            rect: Rect(topLeftX: 100, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 100, topLeftY: 0, width: 1920, height: 1080),
            isMain: true,
        )
        let newSecondary = WorkspaceNamingTestMonitor(
            monitorAppKitNsScreenScreensId: 2,
            name: "Secondary",
            rect: Rect(topLeftX: 2020, topLeftY: 0, width: 1920, height: 1080),
            visibleRect: Rect(topLeftX: 2020, topLeftY: 0, width: 1920, height: 1080),
            isMain: false,
        )
        setMonitorsForTests([newMain, newSecondary])

        gcMonitors()

        XCTAssertTrue(newMain.activeWorkspace === workspace)
    }

    func testSystemStubDoesNotForgetActiveProject() throws {
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        XCTAssertTrue(projectWorkspace.isVisible)

        let stub = replaceActiveWorkspaceWithSystemStubForTests(on: mainMonitor)
        XCTAssertTrue(stub.isSystemStub)
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
        XCTAssertFalse(mainMonitor.activeWorkspace.isSystemStub)
        XCTAssertEqual(mainMonitor.activeWorkspace.projectId, project.id)
        XCTAssertTrue(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).contains(mainMonitor.activeWorkspace))
    }

    func testClosingLastWindowKeepsOneWorkspaceInActiveProject() throws {
        let defaultWorkspace = Workspace.get(byName: "1")
        defaultWorkspace.markAsAutomaticallyNamed()
        _ = TestWindow.new(id: 19, parent: defaultWorkspace.rootTilingContainer)
        let project = createWorkspaceProject()
        let projectWorkspace = try XCTUnwrap(switchWorkspaceProject(project.id, on: mainMonitor))
        let projectWindow = TestWindow.new(id: 20, parent: projectWorkspace.rootTilingContainer)

        Workspace.garbageCollectUnusedWorkspaces()
        projectWindow.unbindFromParent()
        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertTrue(projectWorkspace.isVisible)
        XCTAssertEqual(activeWorkspaceProjectId(for: mainMonitor), project.id)
        XCTAssertFalse(workspaceHasSidebarVisibleWindows(projectWorkspace))
        XCTAssertTrue(userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).contains(projectWorkspace))
        XCTAssertEqual(
            userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
                .filter { $0.scope == workspaceScope(projectId: project.id, monitor: mainMonitor) },
            [projectWorkspace],
        )
    }
}
