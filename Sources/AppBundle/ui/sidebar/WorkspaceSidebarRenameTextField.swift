import AppKit

final class WorkspaceSidebarRenameTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
            case 36, 76:
                onCommit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignFirstResponder() -> Bool {
        super.resignFirstResponder()
    }
}
