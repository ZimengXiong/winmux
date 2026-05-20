import AppKit
import SwiftUI

final class WorkspaceSidebarProjectRenameNSTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        debugWorkspaceSidebarRenameLog("textField becomeFirstResponder result=\(result) windowKey=\(window?.isKeyWindow.description ?? "nil") firstResponder=\(String(describing: window?.firstResponder))")
        return result
    }

    override func resignFirstResponder() -> Bool {
        debugWorkspaceSidebarRenameLog("textField resignFirstResponder windowKey=\(window?.isKeyWindow.description ?? "nil") firstResponder=\(String(describing: window?.firstResponder))")
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        debugWorkspaceSidebarRenameLog("textField keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") stringBefore=\(stringValue)")
        super.keyDown(with: event)
    }
}

struct WorkspaceSidebarProjectRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> NSTextField {
        debugWorkspaceSidebarRenameLog("makeNSView text=\(text)")
        let field = WorkspaceSidebarProjectRenameNSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = .systemFont(ofSize: 12.5, weight: .medium)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.focus(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        debugWorkspaceSidebarRenameLog("updateNSView didFocus=\(context.coordinator.didFocus) text=\(text) field=\(field.stringValue) windowKey=\(field.window?.isKeyWindow.description ?? "nil") firstResponder=\(String(describing: field.window?.firstResponder))")
        if field.stringValue != text {
            field.stringValue = text
        }
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.focus(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onCommit: @MainActor @Sendable () -> Void
        let onCancel: @MainActor @Sendable () -> Void
        var didFocus = false
        var focusAttempts = 0

        init(text: Binding<String>, onCommit: @escaping @MainActor @Sendable () -> Void, onCancel: @escaping @MainActor @Sendable () -> Void) {
            _text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        @MainActor
        func focus(_ field: NSTextField) {
            guard !didFocus else { return }
            guard let window = field.window else {
                debugWorkspaceSidebarRenameLog("focus noWindow attempt=\(focusAttempts)")
                scheduleFocusRetry(field)
                return
            }
            debugWorkspaceSidebarRenameLog("focus attempt=\(focusAttempts) before panelKey=\(WorkspaceSidebarPanel.shared.isKeyWindow) fieldWindowKey=\(window.isKeyWindow) firstResponder=\(String(describing: window.firstResponder))")
            WorkspaceSidebarPanel.shared.prepareForInlineTextEditing()
            window.makeKeyAndOrderFront(nil)
            let didBecomeFirstResponder = window.makeFirstResponder(field)
            field.selectText(nil)
            didFocus = didBecomeFirstResponder && window.isKeyWindow && window.firstResponder === field.currentEditor()
            debugWorkspaceSidebarRenameLog("focus result makeFirstResponder=\(didBecomeFirstResponder) didFocus=\(didFocus) windowKey=\(window.isKeyWindow) firstResponder=\(String(describing: window.firstResponder)) currentEditor=\(String(describing: field.currentEditor())) selectedRange=\(field.currentEditor()?.selectedRange ?? NSRange(location: -1, length: -1))")
            if !didFocus {
                scheduleFocusRetry(field)
            }
        }

        @MainActor
        private func scheduleFocusRetry(_ field: NSTextField) {
            guard focusAttempts < 8 else { return }
            focusAttempts += 1
            debugWorkspaceSidebarRenameLog("scheduleFocusRetry attempt=\(focusAttempts)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak field] in
                guard let self, let field else { return }
                self.focus(field)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
            debugWorkspaceSidebarRenameLog("controlTextDidChange text=\(text)")
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            debugWorkspaceSidebarRenameLog("control command=\(commandSelector) text=\(textView.string)")
            switch commandSelector {
                case #selector(NSResponder.insertNewline(_:)):
                    text = textView.string
                    onCommit()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    onCancel()
                    return true
                default:
                    return false
            }
        }
    }
}

struct WorkspaceSidebarProjectRenameField: View {
    let project: WorkspaceSidebarProjectViewModel
    @Binding var text: String
    let onCommit: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void
    @State private var shouldReplaceSelection = true

    var body: some View {
        WorkspaceSidebarProjectRenameTextField(
            text: $text,
            onCommit: onCommit,
            onCancel: onCancel,
        )
            .padding(.horizontal, 6)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarPlateCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarPlateCornerRadius, style: .continuous)
                    .strokeBorder(workspaceSidebarProjectColor(projectId: project.id, configuredHex: project.colorHex).opacity(0.75), lineWidth: 0.8)
            }
            .onAppear {
                debugWorkspaceSidebarRenameLog("renameField onAppear project=\(project.id.rawValue) text=\(text)")
                shouldReplaceSelection = true
                WorkspaceSidebarPanel.shared.beginInlineTextEditing(
                    onCancel: onCancel,
                    onKeyDown: { key in
                        handleInlineTextKey(key)
                    }
                )
            }
            .onDisappear {
                debugWorkspaceSidebarRenameLog("renameField onDisappear project=\(project.id.rawValue) text=\(text)")
                WorkspaceSidebarPanel.shared.endInlineTextEditing()
            }
    }

    @MainActor
    private func handleInlineTextKey(_ key: WorkspaceSidebarInlineTextKey) {
        switch key {
            case .text(let inserted):
                if shouldReplaceSelection {
                    text = inserted
                    shouldReplaceSelection = false
                } else {
                    text += inserted
                }
            case .deleteBackward:
                if shouldReplaceSelection {
                    text = ""
                    shouldReplaceSelection = false
                } else if !text.isEmpty {
                    text.removeLast()
                }
            case .deleteForward:
                if shouldReplaceSelection {
                    text = ""
                    shouldReplaceSelection = false
                }
            case .commit:
                onCommit()
            case .cancel:
                onCancel()
            case .ignored:
                break
        }
        debugWorkspaceSidebarRenameLog("inlineTextKey applied key=\(key) text=\(text)")
    }
}
