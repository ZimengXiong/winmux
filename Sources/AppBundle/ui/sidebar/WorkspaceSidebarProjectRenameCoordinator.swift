import AppKit

@MainActor
final class WorkspaceSidebarProjectRenameCoordinator: NSObject, NSTextFieldDelegate {
    var parent: WorkspaceSidebarProjectRenameField
    var focusId: String?
    var didResolve = false
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    weak var field: WorkspaceSidebarRenameTextField?
    var outsideInteractionMonitor: Any?

    init(_ parent: WorkspaceSidebarProjectRenameField) {
        self.parent = parent
    }

    func update(parent: WorkspaceSidebarProjectRenameField, field: WorkspaceSidebarRenameTextField) {
        self.parent = parent
        onCommit = parent.onCommit
        onCancel = parent.onCancel
        self.field = field
        installOutsideInteractionMonitor(for: field)
        field.onCommit = { [weak self] in self?.commit() }
        field.onCancel = { [weak self] in self?.cancel() }
    }

    func prepareFocus(field: WorkspaceSidebarRenameTextField, focusId: String) {
        self.focusId = focusId
        didResolve = false
        DispatchQueue.main.async {
            WorkspaceSidebarPanel.shared.prepareForInlineTextEditing()
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        parent.text = field.stringValue
    }
}
