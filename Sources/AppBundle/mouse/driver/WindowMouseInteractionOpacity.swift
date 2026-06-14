import CoreGraphics
import Common
import Darwin
import Foundation

private let mouseInteractionHiddenWindowAlpha: Float = 0
private let mouseInteractionVisibleWindowAlpha: Float = 1

@MainActor
final class WindowMouseInteractionOpacityController {
    static let shared = WindowMouseInteractionOpacityController()

    private var hiddenWindowIds: Set<UInt32> = []
    private var temporarilyMovedWindows: [UInt32: Rect] = [:]

    private init() {}

    func update(activeWindowId: UInt32, hidesPassiveTabGroupChrome: Bool) {
        guard !isUnitTest else { return }
        let nextHiddenIds = nextMouseInteractionHiddenWindowIds(
            activeWindowId: activeWindowId,
            currentlyHidden: hiddenWindowIds,
            discovered: Set(mouseInteractionWindowIdsToHide(activeWindowId: activeWindowId)),
        )
        moveWindowsOutOfView(
            activeWindowId: activeWindowId,
            hidesPassiveTabGroupChrome: hidesPassiveTabGroupChrome,
        )
        setWindowListAlpha(
            windowIds: Array(hiddenWindowIds.subtracting(nextHiddenIds)),
            alpha: mouseInteractionVisibleWindowAlpha,
        )
        setWindowListAlpha(
            windowIds: Array(nextHiddenIds.subtracting(hiddenWindowIds)),
            alpha: mouseInteractionHiddenWindowAlpha,
        )
        hiddenWindowIds = nextHiddenIds
    }

    func restore() {
        if !hiddenWindowIds.isEmpty {
            setWindowListAlpha(windowIds: Array(hiddenWindowIds), alpha: mouseInteractionVisibleWindowAlpha)
        }
        hiddenWindowIds.removeAll()
        suppressPostDragAxObserverEvents(for: temporarilyMovedWindows.keys)
        for (windowId, rect) in temporarilyMovedWindows {
            guard let window = Window.get(byId: windowId) else { continue }
            window.lastKnownActualRect = rect
            window.setAxFrame(rect.topLeftCorner, rect.size)
        }
        temporarilyMovedWindows.removeAll()
        WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
    }

    func shouldSuppressObserverEvent(windowId: UInt32?) -> Bool {
        guard let windowId else { return false }
        return temporarilyMovedWindows.keys.contains(windowId)
    }

    private func moveWindowsOutOfView(activeWindowId: UInt32, hidesPassiveTabGroupChrome: Bool) {
        let windowsToHide = mouseInteractionManagedWindowsToHide(activeWindowId: activeWindowId)
        if hidesPassiveTabGroupChrome {
            WindowTabStripPanelController.shared.setHiddenPassiveTabGroupChrome(
                passiveTabGroupChromeIdsToHide(windows: windowsToHide, activeWindowId: activeWindowId)
            )
        } else {
            WindowTabStripPanelController.shared.clearHiddenPassiveTabGroupChrome()
        }
        let visibleIds = Set(windowsToHide.map(\.windowId))
        for staleId in temporarilyMovedWindows.keys where !visibleIds.contains(staleId) {
            guard let rect = temporarilyMovedWindows.removeValue(forKey: staleId),
                  let window = Window.get(byId: staleId)
            else { continue }
            window.lastKnownActualRect = rect
            window.setAxFrame(rect.topLeftCorner, rect.size)
        }
        for window in windowsToHide where temporarilyMovedWindows[window.windowId] == nil {
            guard let rect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { continue }
            temporarilyMovedWindows[window.windowId] = rect
            window.lastKnownActualRect = rect
            window.setAxFrame(mouseInteractionHiddenTopLeftCorner(for: rect), nil)
        }
    }
}

func nextMouseInteractionHiddenWindowIds(
    activeWindowId: UInt32,
    currentlyHidden: Set<UInt32>,
    discovered: Set<UInt32>,
) -> Set<UInt32> {
    var result = discovered
    result.formUnion(currentlyHidden)
    result.remove(activeWindowId)
    return result
}

@MainActor
private func passiveTabGroupChromeIdsToHide(windows: [Window], activeWindowId: UInt32) -> Set<ObjectIdentifier> {
    let activeTabGroup = Window.get(byId: activeWindowId)?.nearestWindowTabGroup
    return Set(windows.compactMap { window in
        guard let tabGroup = window.nearestWindowTabGroup,
              tabGroup.usesWindowTabBehavior,
              tabGroup !== activeTabGroup
        else {
            return nil
        }
        return ObjectIdentifier(tabGroup)
    })
}

@MainActor
func mouseInteractionWindowIdsToHide(activeWindowId: UInt32) -> [UInt32] {
    var windowIds = Set(mouseInteractionManagedWindowIdsToHide(activeWindowId: activeWindowId))
    windowIds.formUnion(mouseInteractionVisibleWindowIdsToHide(activeWindowId: activeWindowId))
    return Array(windowIds)
}

@MainActor
private func mouseInteractionManagedWindowIdsToHide(activeWindowId: UInt32) -> [UInt32] {
    MacWindow.allWindows.compactMap { window in
        guard window.windowId != activeWindowId,
              !window.isHiddenInCorner,
              window.nodeWorkspace?.isVisible == true
        else {
            return nil
        }
        return window.windowId
    }
}

private func mouseInteractionVisibleWindowIdsToHide(activeWindowId: UInt32) -> [UInt32] {
    mouseInteractionVisibleWindowsToHide(activeWindowId: activeWindowId).map(\.id)
}

@MainActor
private func mouseInteractionManagedWindowsToHide(activeWindowId: UInt32) -> [Window] {
    MacWindow.allWindows.compactMap { window in
        guard window.windowId != activeWindowId,
              !window.isHiddenInCorner,
              window.nodeWorkspace?.isVisible == true
        else {
            return nil
        }
        return window
    }
}

private struct MouseInteractionVisibleWindow {
    let id: UInt32
}

private func mouseInteractionVisibleWindowsToHide(activeWindowId: UInt32) -> [MouseInteractionVisibleWindow] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windowInfos = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
        return []
    }

    let currentProcessId = ProcessInfo.processInfo.processIdentifier
    return windowInfos.compactMap { info in
        guard let windowId = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              windowId != activeWindowId,
              let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
              layer == 0,
              let ownerProcessId = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
              ownerProcessId != currentProcessId,
              let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
              alpha > 0.01,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.width > 8,
              bounds.height > 8
        else {
            return nil
        }
        return MouseInteractionVisibleWindow(id: windowId)
    }
}

private func mouseInteractionHiddenTopLeftCorner(for rect: Rect) -> CGPoint {
    let monitorRect = rect.center.monitorApproximation.visibleRect
    return monitorRect.bottomRightCorner + CGPoint(x: 8, y: 8)
}

@MainActor
private func setWindowListAlpha(windowIds: [UInt32], alpha: Float) {
    guard !windowIds.isEmpty else { return }
    let skyLight = SLSWindowAlpha.shared
    if let setWindowListAlpha = skyLight.setWindowListAlpha {
        let ids = windowIds
        _ = ids.withUnsafeBufferPointer { buffer in
            setWindowListAlpha(skyLight.connectionId, buffer.baseAddress, Int32(buffer.count), alpha)
        }
        return
    }
    guard let setWindowAlpha = skyLight.setWindowAlpha else { return }
    for windowId in windowIds {
        _ = setWindowAlpha(skyLight.connectionId, windowId, alpha)
    }
}

@MainActor
private final class SLSWindowAlpha {
    static let shared = SLSWindowAlpha()

    typealias MainConnectionIdFunction = @convention(c) () -> Int32
    typealias SetWindowAlphaFunction = @convention(c) (Int32, UInt32, Float) -> CGError
    typealias SetWindowListAlphaFunction = @convention(c) (Int32, UnsafePointer<UInt32>?, Int32, Float) -> CGError

    let connectionId: Int32
    let setWindowAlpha: SetWindowAlphaFunction?
    let setWindowListAlpha: SetWindowListAlphaFunction?

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
            connectionId = 0
            setWindowAlpha = nil
            setWindowListAlpha = nil
            return
        }
        let mainConnection = dlsym(handle, "SLSMainConnectionID")
            .map { unsafeBitCast($0, to: MainConnectionIdFunction.self) }
        setWindowAlpha = dlsym(handle, "SLSSetWindowAlpha")
            .map { unsafeBitCast($0, to: SetWindowAlphaFunction.self) }
        setWindowListAlpha = dlsym(handle, "SLSSetWindowListAlpha")
            .map { unsafeBitCast($0, to: SetWindowListAlphaFunction.self) }
        connectionId = mainConnection?() ?? 0
    }
}
