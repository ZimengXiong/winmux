@MainActor
func focusWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  let liveFocus = window.toLiveFocusOrNil()
            else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            window.markAsMostRecentChild()
            _ = setFocus(to: liveFocus)
            window.nativeFocus()
        }
    }
}

@MainActor
func focusWindowFromTabStripClick(_ windowId: UInt32, fallbackWorkspace: String) {
    if isWindowTabStripDragInProgress(), !isLeftMouseButtonDown {
        cancelManipulatedWithMouseState()
    }
    focusWindowFromTabStrip(windowId, fallbackWorkspace: fallbackWorkspace)
}
