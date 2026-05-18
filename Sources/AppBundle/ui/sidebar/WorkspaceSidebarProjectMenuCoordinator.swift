import AppKit

@MainActor
final class WorkspaceSidebarProjectMenuCoordinator: NSObject, NSMenuDelegate {
    static let automaticColorValue = "__automatic__"

    var parent: WorkspaceSidebarProjectMenuButton
    var activeMenu: NSMenu?

    init(_ parent: WorkspaceSidebarProjectMenuButton) {
        self.parent = parent
    }

    func menuDidClose(_ menu: NSMenu) {
        activeMenu = nil
    }

    @objc func selectProject(_ item: NSMenuItem) {
        guard let projectId = item.representedObject as? WorkspaceProjectId else { return }
        parent.onSelectProject(projectId)
    }

    @objc func createProject(_ item: NSMenuItem) {
        parent.onCreateProject()
    }

    @objc func renameProject(_ item: NSMenuItem) {
        parent.onRenameSelectedProject()
    }

    @objc func setColor(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String else { return }
        parent.onSetSelectedProjectColor(value == Self.automaticColorValue ? nil : value)
    }

    @objc func deleteProject(_ item: NSMenuItem) {
        parent.onDeleteSelectedProject()
    }
}
