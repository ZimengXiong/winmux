struct FocusAfterWindowClosureReplacement {
    let closingWindow: Window
    let deadWindowWorkspace: Workspace

    @MainActor
    func isValid(_ candidate: LiveFocus?) -> Bool {
        candidate?.windowOrNil != closingWindow &&
            candidate?.workspace == deadWindowWorkspace &&
            candidate?.windowOrNil?.participatesInWorkspaceFocus != false
    }

    @MainActor
    func snapshotTabGroupFocus(
        closeFallback: LiveFocus?,
        previousFocus: LiveFocus?,
        previousPreviousFocus: LiveFocus?,
        currentFocus: LiveFocus,
    ) -> LiveFocus? {
        let closeFallbackTabGroup = nearestTabGroupTabContainer(closeFallback)
        let previousFocusTabGroup = nearestTabGroupTabContainer(previousFocus)
        let previousPreviousFocusTabGroup = nearestTabGroupTabContainer(previousPreviousFocus)

        if isValid(closeFallback),
           isValid(previousFocus),
           closeFallback?.windowOrNil != previousFocus?.windowOrNil,
           closeFallbackTabGroup != nil,
           closeFallbackTabGroup === previousFocusTabGroup
        {
            debugFocusLog(
                "focusAfterWindowClosure closing=\(closingWindow.windowId) preferSnapshotPreviousFocusWithinSameTabGroup=\(debugDescribe(previousFocus)) snapshotCloseFallback=\(debugDescribe(closeFallback)) current=\(debugDescribe(currentFocus))"
            )
            return previousFocus
        }

        if previousFocus?.windowOrNil == closingWindow,
           isValid(closeFallback),
           isValid(previousPreviousFocus),
           closeFallback?.windowOrNil != previousPreviousFocus?.windowOrNil,
           closeFallbackTabGroup != nil,
           closeFallbackTabGroup === previousPreviousFocusTabGroup
        {
            debugFocusLog(
                "focusAfterWindowClosure closing=\(closingWindow.windowId) preferSnapshotPreviousPreviousFocusWithinSameTabGroup=\(debugDescribe(previousPreviousFocus)) snapshotCloseFallback=\(debugDescribe(closeFallback)) snapshotPrev=\(debugDescribe(previousFocus)) current=\(debugDescribe(currentFocus))"
            )
            return previousPreviousFocus
        }
        return nil
    }

    @MainActor
    func shouldPreferSnapshotCloseFallback(
        closeFallback: LiveFocus?,
        currentFocus: LiveFocus,
        previousFocus: LiveFocus?,
    ) -> Bool {
        isValid(closeFallback) &&
            closeFallback?.windowOrNil != currentFocus.windowOrNil &&
            currentFocus.windowOrNil?.app.pid == closingWindow.app.pid &&
            previousFocus?.windowOrNil != closingWindow
    }

    @MainActor
    private func nearestTabGroupTabContainer(_ candidate: LiveFocus?) -> TilingContainer? {
        candidate?.windowOrNil?.parentsWithSelf
            .lazy
            .compactMap { $0 as? TilingContainer }
            .first(where: { $0.layout == .tabGroup && $0.children.count > 1 })
    }
}
