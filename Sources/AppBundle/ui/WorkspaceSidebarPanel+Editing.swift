import AppKit

extension WorkspaceSidebarPanel {
    func beginInlineTextEditing() {
        inlineTextEditingActive = true
        prepareForInlineTextEditing()
    }

    func endInlineTextEditing() {
        guard inlineTextEditingActive else { return }
        inlineTextEditingActive = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func prepareForInlineTextEditing() {
        cancelExpansionWork()
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}
