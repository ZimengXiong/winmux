import AppKit

extension WorkspaceSidebarProjectRenameCoordinator {
    func handleOutsideInteraction(
        _ event: NSEvent,
        field: WorkspaceSidebarRenameTextField,
    ) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            cancel()
            return nil
        }
        if event.type == .keyDown {
            return event
        }
        guard event.window === field.window else {
            commit()
            return event
        }
        let localPoint = field.convert(event.locationInWindow, from: nil)
        if !field.bounds.contains(localPoint) {
            commit()
        }
        return event
    }
}
