import AppKit

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
    // Make the switch feel instant: place the newly active tab into the spot the currently
    // visible tab occupies BEFORE raising it, so it appears in position immediately. The old
    // tab stays beneath it and is hidden later by the scheduled refresh's layout pass — that
    // delay is invisible because the new window already covers it.
    let isTabSwitch: Bool
    if let tabGroup = window.nearestWindowTabGroup, tabGroup.usesWindowTabBehavior,
       window.parent === tabGroup,
       let visibleRect = tabGroup.tabActiveWindow?.lastAppliedLayoutPhysicalRect
    {
        isTabSwitch = true
        // setFrame on the app thread is a no-op when the frame already matches, so this is
        // cheap when re-clicking the active tab.
        window.setAxFrame(visibleRect.topLeftCorner, CGSize(width: visibleRect.width, height: visibleRect.height))
    } else {
        isTabSwitch = false
    }
    window.markAsMostRecentChild()
    _ = setFocus(to: liveFocus)
    window.nativeFocus()
    Task { @MainActor in
        await updateWindowTabModel()
    }
    // Within a tab group no new windows can appear, so skip the heavy refresh barrier.
    scheduleRefreshSession(isTabSwitch ? .onTabSwitched : .menuBarButton)
}

@MainActor
func focusWindowFromTabStripClick(_ windowId: UInt32, fallbackWorkspace: String) {
    if isWindowTabStripDragInProgress(), !isLeftMouseButtonDown {
        cancelManipulatedWithMouseState()
    }
    focusWindowFromTabStrip(windowId, fallbackWorkspace: fallbackWorkspace)
}
