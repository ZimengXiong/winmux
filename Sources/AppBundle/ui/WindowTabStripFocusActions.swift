@MainActor
func focusWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard TrayMenuModel.shared.isEnabled else { return }
    guard let window = Window.get(byId: windowId),
          let liveFocus = window.toLiveFocusOrNil()
    else {
        _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
        scheduleRefreshSession(.menuBarButton)
        return
    }
    window.markAsMostRecentChild()
    _ = setFocus(to: liveFocus)
    window.nativeFocus()
    Task { @MainActor in
        await updateWindowTabModel()
    }
    scheduleRefreshSession(.menuBarButton)
}

@MainActor
func focusWindowFromTabStripClick(_ windowId: UInt32, fallbackWorkspace: String) {
    if isWindowTabStripDragInProgress(), !isLeftMouseButtonDown {
        cancelManipulatedWithMouseState()
    }
    focusWindowFromTabStrip(windowId, fallbackWorkspace: fallbackWorkspace)
}
