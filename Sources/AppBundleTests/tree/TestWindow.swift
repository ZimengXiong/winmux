@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    private var _isHiddenInCorner: Bool = false
    // Mutating the fake native state models a real state transition, which in production is
    // always accompanied by an AX event that invalidates the last-known-native-state cache.
    @MainActor var nativeIsMacosFullscreen: Bool = false {
        didSet { invalidateLastKnownNativeState() }
    }
    @MainActor var nativeIsMacosMinimized: Bool = false {
        didSet { invalidateLastKnownNativeState() }
    }

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
        recordAuthoritativeActualRect(rect)
    }

    @discardableResult
    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat = 1, rect: Rect? = nil) -> TestWindow {
        let wi = TestWindow(id, parent, adaptiveWeight, rect)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    override var title: String {
        get async { // redundant async. todo create bug report to Swift
            description
        }
    }

    @MainActor override func getAxRect() async throws -> Rect? { // todo change to not Optional
        recordAuthoritativeActualRect(_rect)
        return _rect
    }

    @MainActor private(set) var nativeStateFetchCount = 0

    @MainActor override var isMacosFullscreen: Bool {
        get async throws {
            nativeStateFetchCount += 1
            return nativeIsMacosFullscreen
        }
    }

    @MainActor override var isMacosMinimized: Bool {
        get async throws {
            nativeStateFetchCount += 1
            return nativeIsMacosMinimized
        }
    }

    override var isHiddenInCorner: Bool { _isHiddenInCorner }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        let currentRect = _rect ?? Rect(topLeftX: topLeft?.x ?? 0, topLeftY: topLeft?.y ?? 0, width: size?.width ?? 0, height: size?.height ?? 0)
        _rect = Rect(
            topLeftX: topLeft?.x ?? currentRect.topLeftX,
            topLeftY: topLeft?.y ?? currentRect.topLeftY,
            width: size?.width ?? currentRect.width,
            height: size?.height ?? currentRect.height,
        )
        let windowId = self.windowId
        let rect = _rect
        Task { @MainActor in
            Window.get(byId: windowId)?.recordAuthoritativeActualRect(rect)
        }
        _isHiddenInCorner = false
    }
}
