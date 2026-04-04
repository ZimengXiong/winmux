@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    private var _isHiddenInCorner: Bool = false
    var nativeIsMacosFullscreen: Bool = false
    var nativeIsMacosMinimized: Bool = false

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
        lastKnownActualRect = rect
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
        lastKnownActualRect = _rect
        return _rect
    }

    @MainActor override var isMacosFullscreen: Bool { get async throws { nativeIsMacosFullscreen } }

    @MainActor override var isMacosMinimized: Bool { get async throws { nativeIsMacosMinimized } }

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
            Window.get(byId: windowId)?.lastKnownActualRect = rect
        }
        _isHiddenInCorner = false
    }
}
