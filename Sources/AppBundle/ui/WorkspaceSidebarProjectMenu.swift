import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarProjectMenuButton: NSViewRepresentable {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let selectedProjectName: String
    let width: CGFloat
    let isHovered: Bool
    let canDeleteSelectedProject: Bool
    let onSelectProject: (WorkspaceProjectId) -> Void
    let onCreateProject: () -> Void
    let onRenameSelectedProject: () -> Void
    let onSetSelectedProjectColor: (String?) -> Void
    let onDeleteSelectedProject: () -> Void

    func makeCoordinator() -> WorkspaceSidebarProjectMenuCoordinator {
        WorkspaceSidebarProjectMenuCoordinator(self)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarProjectMenuControl {
        let control = WorkspaceSidebarProjectMenuControl()
        control.target = context.coordinator
        control.action = #selector(WorkspaceSidebarProjectMenuCoordinator.openMenu(_:))
        return control
    }

    func updateNSView(_ control: WorkspaceSidebarProjectMenuControl, context: Context) {
        context.coordinator.parent = self
        control.update(title: selectedProjectName, width: width, isHovered: isHovered)
    }

}
