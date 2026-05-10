import CoreGraphics
import Common
import Darwin

private let mouseInteractionHiddenWindowAlpha: Float = 0
private let mouseInteractionVisibleWindowAlpha: Float = 1

@MainActor
final class WindowMouseInteractionOpacityController {
    static let shared = WindowMouseInteractionOpacityController()

    private var hiddenWindowIds: Set<UInt32> = []

    private init() {}

    func update(activeWindowId: UInt32) {
        guard !isUnitTest else { return }
        let nextHiddenIds = Set(mouseInteractionWindowIdsToHide(activeWindowId: activeWindowId))
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
        guard !hiddenWindowIds.isEmpty else { return }
        setWindowListAlpha(windowIds: Array(hiddenWindowIds), alpha: mouseInteractionVisibleWindowAlpha)
        hiddenWindowIds.removeAll()
    }
}

@MainActor
func mouseInteractionWindowIdsToHide(activeWindowId: UInt32) -> [UInt32] {
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
