import AppKit
import SwiftUI

struct WorkspaceSidebarProjectRenameField: NSViewRepresentable {
    @Binding var text: String
    let focusId: String
    let alignment: NSTextAlignment
    let fontSize: CGFloat
    let fontWeight: NSFont.Weight
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> WorkspaceSidebarProjectRenameCoordinator {
        WorkspaceSidebarProjectRenameCoordinator(self)
    }

    func makeNSView(context: Context) -> WorkspaceSidebarRenameTextField {
        let field = WorkspaceSidebarRenameTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ field: WorkspaceSidebarRenameTextField, context: Context) {
        context.coordinator.update(parent: self, field: field)
        field.alignment = alignment
        field.font = .systemFont(ofSize: fontSize, weight: fontWeight)
        field.textColor = .white
        if field.stringValue != text {
            field.stringValue = text
        }
        guard context.coordinator.focusId != focusId else { return }
        context.coordinator.prepareFocus(field: field, focusId: focusId)
    }

    static func dismantleNSView(_ field: WorkspaceSidebarRenameTextField, coordinator: WorkspaceSidebarProjectRenameCoordinator) {
        coordinator.removeOutsideInteractionMonitor()
        field.onCommit = nil
        field.onCancel = nil
        WorkspaceSidebarPanel.shared.endInlineTextEditing()
    }
}
