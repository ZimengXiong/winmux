import AppKit

extension WorkspaceSidebarProjectRenameCoordinator {
    func installOutsideInteractionMonitor(for field: WorkspaceSidebarRenameTextField) {
        guard outsideInteractionMonitor == nil else { return }
        outsideInteractionMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
        ) { [weak self, weak field] event in
            guard let self, let field else { return event }
            return self.handleOutsideInteraction(event, field: field)
        }
    }

    func removeOutsideInteractionMonitor() {
        if let outsideInteractionMonitor {
            NSEvent.removeMonitor(outsideInteractionMonitor)
            self.outsideInteractionMonitor = nil
        }
    }

    func commit() {
        guard !didResolve else { return }
        didResolve = true
        if let field {
            parent.text = field.stringValue
            field.window?.makeFirstResponder(nil)
        }
        removeOutsideInteractionMonitor()
        onCommit?()
    }

    func cancel() {
        guard !didResolve else { return }
        didResolve = true
        field?.window?.makeFirstResponder(nil)
        removeOutsideInteractionMonitor()
        onCancel?()
    }
}
