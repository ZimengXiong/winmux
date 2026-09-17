import Foundation

@MainActor
func focusAfterWindowClosure(
    closingWindow: Window,
    focusedWindowIdBeforeClosure: UInt32?,
    deadWindowWorkspace: Workspace?,
    currentFocus: LiveFocus,
    previousFocus: LiveFocus?,
    previousPreviousFocus: LiveFocus?,
    refreshSnapshotCloseFallback: LiveFocus?,
    refreshSnapshotPreviousFocus: LiveFocus?,
    refreshSnapshotPreviousPreviousFocus: LiveFocus?,
    previousFocusedWorkspace: Workspace?,
    previousFocusedWorkspaceDate: Date,
    now: Date = .now,
) -> LiveFocus? {
    // Only the closure of the focused window may move focus. This used to run for every closure,
    // so a short-lived window the user never touched -- Telegram opens and closes one around its
    // fullscreen video viewer, and it is classified as a floating dialog rather than a popup, so
    // the popup exemption below does not cover it -- reached the focus-history fallbacks and threw
    // the user out of the window they were working in, often into a different application.
    //
    // `currentFocus` cannot answer "was this window focused": the caller has already unbound the
    // window, so `focus` has fallen back to something else and never equals the closing window.
    // The refresh session's snapshot can -- it is taken at the start of the session, before
    // macOS' own post-close focus reshuffle is read into the model.
    guard focusedWindowIdBeforeClosure == closingWindow.windowId else {
        debugFocusLog(
            "focusAfterWindowClosure closing=\(closingWindow.windowId) skippedNotFocused focusedBefore=\(focusedWindowIdBeforeClosure?.description ?? "nil") currentFocus=\(debugDescribe(currentFocus))"
        )
        return nil
    }
    guard let deadWindowWorkspace else { return nil }
    guard deadWindowWorkspace == currentFocus.workspace ||
        deadWindowWorkspace == previousFocusedWorkspace && previousFocusedWorkspaceDate.distance(to: now) < 1
    else {
        debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) skipped currentFocus=\(debugDescribe(currentFocus)) previousFocusedWorkspace=\(previousFocusedWorkspace?.name ?? "nil")")
        return nil
    }

    let replacement = FocusAfterWindowClosureReplacement(closingWindow: closingWindow, deadWindowWorkspace: deadWindowWorkspace)
    if let snapshotTabFocus = replacement.snapshotTabGroupFocus(
        closeFallback: refreshSnapshotCloseFallback,
        previousFocus: refreshSnapshotPreviousFocus,
        previousPreviousFocus: refreshSnapshotPreviousPreviousFocus,
        currentFocus: currentFocus,
    ) {
        return snapshotTabFocus
    }

    if replacement.shouldPreferSnapshotCloseFallback(
        closeFallback: refreshSnapshotCloseFallback,
        currentFocus: currentFocus,
        previousFocus: refreshSnapshotPreviousFocus,
    ) {
        debugFocusLog(
            "focusAfterWindowClosure closing=\(closingWindow.windowId) preferSnapshotCloseFallback=\(debugDescribe(refreshSnapshotCloseFallback)) current=\(debugDescribe(currentFocus)) snapshotPrev=\(debugDescribe(refreshSnapshotPreviousFocus))"
        )
        return refreshSnapshotCloseFallback
    }

    let fallbackHistory: [LiveFocus?] = [
        refreshSnapshotCloseFallback,
        refreshSnapshotPreviousFocus,
        previousFocus,
        (refreshSnapshotPreviousFocus?.windowOrNil == closingWindow) ? refreshSnapshotPreviousPreviousFocus : nil,
        (previousFocus?.windowOrNil == closingWindow) ? previousPreviousFocus : nil,
    ]
    for candidate in fallbackHistory where replacement.isValid(candidate) {
        debugFocusLog(
            "focusAfterWindowClosure closing=\(closingWindow.windowId) choseCandidate=\(debugDescribe(candidate)) current=\(debugDescribe(currentFocus)) snapshotCloseFallback=\(debugDescribe(refreshSnapshotCloseFallback)) snapshotPrev=\(debugDescribe(refreshSnapshotPreviousFocus)) snapshotPrevPrev=\(debugDescribe(refreshSnapshotPreviousPreviousFocus)) prev=\(debugDescribe(previousFocus)) prevPrev=\(debugDescribe(previousPreviousFocus))"
        )
        return candidate
    }

    let fallback = deadWindowWorkspace.toLiveFocus()
    debugFocusLog("focusAfterWindowClosure closing=\(closingWindow.windowId) defaultFallback=\(debugDescribe(fallback))")
    return fallback
}
