import Common
import Foundation

@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

@MainActor private struct WorkspaceProjectFocusHold {
    let projectId: WorkspaceProjectId
    let expiresAt: Date
}

@MainActor private var workspaceProjectFocusHold: WorkspaceProjectFocusHold? = nil

@MainActor
func resetFocusCacheForTests() {
    lastKnownNativeFocusedWindowId = nil
    workspaceProjectFocusHold = nil
}

@MainActor
func holdFocusOnWorkspaceProject(_ projectId: WorkspaceProjectId, for duration: TimeInterval) {
    workspaceProjectFocusHold = WorkspaceProjectFocusHold(
        projectId: projectId,
        expiresAt: Date().addingTimeInterval(duration),
    )
}

@MainActor
func clearFocusOnWorkspaceProjectHold(_ projectId: WorkspaceProjectId? = nil) {
    guard projectId == nil || workspaceProjectFocusHold?.projectId == projectId else { return }
    workspaceProjectFocusHold = nil
}

@MainActor
private func activeWorkspaceProjectFocusHold(now: Date = .now) -> WorkspaceProjectFocusHold? {
    guard let hold = workspaceProjectFocusHold else { return nil }
    if hold.expiresAt <= now {
        workspaceProjectFocusHold = nil
        return nil
    }
    return hold
}

@MainActor
private func shouldIgnoreNativeFocusDuringProjectHold(_ nativeFocused: Window?) -> Bool {
    guard let hold = activeWorkspaceProjectFocusHold(),
          let nativeFocused
    else {
        return false
    }
    return nativeFocused.visualWorkspace?.projectId != hold.projectId
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    let lastKnownNativeFocusedWindowIdBefore = lastKnownNativeFocusedWindowId
    if shouldIgnoreNativeFocusDuringProjectHold(nativeFocused) {
        lastKnownNativeFocusedWindowId = nil
        debugFocusLog(
            "updateFocusCache ignoredProjectHold event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") heldProject=\(activeWorkspaceProjectFocusHold()?.projectId.rawValue ?? "nil") logicalFocus=\(debugDescribe(focus))"
        )
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    (nativeFocused?.app as? MacApp)?.lastNativeFocusedWindowId = nativeFocused?.windowId
    debugFocusLog(
        "updateFocusCache event=\(refreshSessionEvent.prettyDescription) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") lastKnownNative=\(lastKnownNativeFocusedWindowIdBefore?.description ?? "nil") -> \(lastKnownNativeFocusedWindowId?.description ?? "nil") logicalFocus=\(debugDescribe(focus))"
    )
}
