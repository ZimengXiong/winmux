import AppKit
import Common

@MainActor
final class WindowMouseInteractionDriver {
    static let shared = WindowMouseInteractionDriver()

    private struct MoveSession: Equatable {
        let windowId: UInt32
        let subject: WindowDragSubject
        let detachOrigin: TabDetachOrigin
        let startedInSidebar: Bool
    }

    private struct ResizeSession: Equatable {
        let windowId: UInt32
    }

    private struct ResizePrediction {
        let windowId: UInt32
        let baseRect: Rect
        let edges: ResizePredictionEdges
        let mouseOffset: ResizePredictionMouseOffset
        var latestRect: Rect

        func predictedRect(mouse: CGPoint) -> Rect {
            let minimumWidth = CGFloat(80)
            let minimumHeight = CGFloat(80)
            var minX = baseRect.minX
            var maxX = baseRect.maxX
            var minY = baseRect.minY
            var maxY = baseRect.maxY

            if edges.left {
                minX = min(mouse.x - mouseOffset.left, maxX - minimumWidth)
            }
            if edges.right {
                maxX = max(mouse.x - mouseOffset.right, minX + minimumWidth)
            }
            if edges.up {
                minY = min(mouse.y - mouseOffset.up, maxY - minimumHeight)
            }
            if edges.down {
                maxY = max(mouse.y - mouseOffset.down, minY + minimumHeight)
            }

            return Rect(topLeftX: minX, topLeftY: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private struct ResizePredictionEdges {
        let left: Bool
        let right: Bool
        let up: Bool
        let down: Bool

        var hasAny: Bool { left || right || up || down }
    }

    private struct ResizePredictionMouseOffset {
        let left: CGFloat
        let right: CGFloat
        let up: CGFloat
        let down: CGFloat
    }

    private var moveSession: MoveSession?
    private var resizeSession: ResizeSession?
    private var resizePrediction: ResizePrediction?
    private var isResizeSampleInFlight = false
    private var isMouseUpResetScheduled = false

    private init() {}

    func startMove(
        windowId: UInt32,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
        startedInSidebar: Bool,
    ) {
        let session = MoveSession(
            windowId: windowId,
            subject: subject,
            detachOrigin: detachOrigin,
            startedInSidebar: startedInSidebar,
        )
        if moveSession != session {
            WindowDragFrameGate.shared.reset(windowId: windowId)
        }
        moveSession = session
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        startDisplayLoop()
        renderMoveFrame(force: true)
    }

    func startResize(windowId: UInt32) {
        let session = ResizeSession(windowId: windowId)
        if resizeSession != session {
            resizePrediction = nil
            isResizeSampleInFlight = false
            isMouseUpResetScheduled = false
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        setCurrentMouseManipulationKind(.resize)
        clearPendingWindowDragIntent()
        clearPendingUnmanagedWindowSnap()
        WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
        if let window = Window.get(byId: windowId) {
            if let rect = window.lastAppliedLayoutPhysicalRect ?? window.lastKnownActualRect {
                updateCompositedResizePreview(window, rect: rect)
            }
        }
        startDisplayLoop()
        sampleResizeFrame(force: true)
    }

    func noteGlobalDragActivity() {
        if moveSession != nil {
            renderMoveFrame(force: false)
        }
        if resizeSession != nil {
            sampleResizeFrame(force: false)
        }
    }

    func flushBeforeMouseUp() async {
        if moveSession != nil {
            renderMoveFrame(force: true)
        }
        guard let resizeSession else { return }
        defer {
            if self.resizeSession == resizeSession {
                self.resizeSession = nil
            }
            resizePrediction = nil
            isResizeSampleInFlight = false
            WindowResizePreviewPanel.shared.hide()
        }
        guard let window = Window.get(byId: resizeSession.windowId) else { return }
        guard let rect = await finalResizeRect(for: resizeSession, window: window) else { return }
        guard self.resizeSession == resizeSession else { return }
        updateCompositedResizePreview(window, rect: rect)
        applyResizeWithMouse(window, rect: rect)
    }

    func stop() {
        DisplayRefreshDriver.shared.remove(owner: self)
        moveSession = nil
        resizeSession = nil
        resizePrediction = nil
        isResizeSampleInFlight = false
        isMouseUpResetScheduled = false
        WindowResizePreviewPanel.shared.hide()
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
    }

    private func startDisplayLoop() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.displayFrame()
        }
    }

    private func displayFrame() {
        guard isLeftMouseButtonDown else {
            finishAfterMissedMouseUpIfNeeded()
            return
        }
        renderMoveFrame(force: false)
        sampleResizeFrame(force: false)
    }

    private func finishAfterMissedMouseUpIfNeeded() {
        guard resizeSession != nil || moveSession != nil else {
            DisplayRefreshDriver.shared.remove(owner: self)
            WindowResizePreviewPanel.shared.hide()
            return
        }
        guard !isMouseUpResetScheduled else { return }
        isMouseUpResetScheduled = true
        DisplayRefreshDriver.shared.remove(owner: self)
        Task { @MainActor in
            try? await resetManipulatedWithMouseIfPossible()
            isMouseUpResetScheduled = false
        }
    }

    private func renderMoveFrame(force: Bool) {
        guard let session = moveSession else { return }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .move else { return }
        guard currentlyManipulatedWithMouseWindowId == session.windowId,
              let sourceWindow = Window.get(byId: session.windowId)
        else {
            clearPendingWindowDragIntent()
            clearPendingUnmanagedWindowSnap()
            stop()
            return
        }

        let currentMouseLocation = mouseLocation
        _ = WindowDragFrameGate.shared.shouldProcess(
            windowId: sourceWindow.windowId,
            point: currentMouseLocation,
            force: force,
        )

        if config.enableWindowManagement {
            renderManagedMoveFrame(
                sourceWindow: sourceWindow,
                mouseLocation: currentMouseLocation,
                session: session,
            )
        } else {
            renderUnmanagedMoveFrame(
                sourceWindow: sourceWindow,
                mouseLocation: currentMouseLocation,
                session: session,
            )
        }
    }

    private func renderManagedMoveFrame(
        sourceWindow: Window,
        mouseLocation: CGPoint,
        session: MoveSession,
    ) {
        switch sourceWindow.parent?.cases {
            case .workspace:
                moveFloatingWindowWithMouse(sourceWindow)
                clearPendingUnmanagedWindowSnap()
            case .tilingContainer:
                clearPendingUnmanagedWindowSnap()
                _ = updatePendingWindowDragIntent(
                    sourceWindow: sourceWindow,
                    mouseLocation: mouseLocation,
                    subject: session.subject,
                    detachOrigin: session.detachOrigin,
                )
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer, nil:
                clearPendingWindowDragIntent()
                clearPendingUnmanagedWindowSnap()
        }
    }

    private func renderUnmanagedMoveFrame(
        sourceWindow: Window,
        mouseLocation: CGPoint,
        session: MoveSession,
    ) {
        let didUpdateIntent = updatePendingWindowDragIntent(
            sourceWindow: sourceWindow,
            mouseLocation: mouseLocation,
            subject: session.subject,
            detachOrigin: session.detachOrigin,
        )
        if didUpdateIntent {
            clearPendingUnmanagedWindowSnap()
        } else if session.subject == .window,
                  !session.startedInSidebar,
                  session.detachOrigin == .window
        {
            refreshPendingUnmanagedWindowSnap(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
        } else {
            clearPendingUnmanagedWindowSnap()
        }
    }

    private func sampleResizeFrame(force: Bool) {
        guard let session = resizeSession else { return }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .resize else { return }
        guard let window = Window.get(byId: session.windowId) else {
            stop()
            return
        }

        if var prediction = resizePrediction, prediction.windowId == session.windowId {
            let rect = prediction.predictedRect(mouse: mouseLocation)
            prediction.latestRect = rect
            resizePrediction = prediction
            updateCompositedResizePreview(window, rect: rect)
            return
        }

        guard force || !isResizeSampleInFlight else { return }
        isResizeSampleInFlight = true
        let sessionWindowId = session.windowId
        Task { @MainActor in
            defer { isResizeSampleInFlight = false }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            guard let rect = try? await window.getAxRect() else { return }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            resizePrediction = makeResizePrediction(window: window, observedRect: rect)
            updateCompositedResizePreview(window, rect: rect)
        }
    }

    private func finalResizeRect(for session: ResizeSession, window: Window) async -> Rect? {
        if let resizePrediction, resizePrediction.windowId == session.windowId {
            return resizePrediction.predictedRect(mouse: mouseLocation)
        }
        if let rect = try? await window.getAxRect() {
            return rect
        }
        if let resizePrediction, resizePrediction.windowId == session.windowId {
            return resizePrediction.latestRect
        }
        return window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
    }

    private func makeResizePrediction(window: Window, observedRect: Rect) -> ResizePrediction? {
        let mouse = mouseLocation
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        let edges = resizePredictionEdges(baseRect: baseRect, observedRect: observedRect, mouse: mouse)
        guard edges.hasAny else { return nil }
        return ResizePrediction(
            windowId: window.windowId,
            baseRect: observedRect,
            edges: edges,
            mouseOffset: ResizePredictionMouseOffset(
                left: mouse.x - observedRect.minX,
                right: mouse.x - observedRect.maxX,
                up: mouse.y - observedRect.minY,
                down: mouse.y - observedRect.maxY,
            ),
            latestRect: observedRect,
        )
    }

    private func resizePredictionEdges(baseRect: Rect, observedRect: Rect, mouse: CGPoint) -> ResizePredictionEdges {
        let threshold = CGFloat(2)
        let leftDiff = abs(baseRect.minX - observedRect.minX)
        let rightDiff = abs(baseRect.maxX - observedRect.maxX)
        let upDiff = abs(baseRect.minY - observedRect.minY)
        let downDiff = abs(baseRect.maxY - observedRect.maxY)

        var left = leftDiff > threshold
        var right = rightDiff > threshold
        var up = upDiff > threshold
        var down = downDiff > threshold

        if left, right {
            left = leftDiff >= rightDiff
            right = !left
        }
        if up, down {
            up = upDiff >= downDiff
            down = !up
        }

        if !left, !right {
            let leftDistance = abs(mouse.x - observedRect.minX)
            let rightDistance = abs(mouse.x - observedRect.maxX)
            if min(leftDistance, rightDistance) <= 96 {
                left = leftDistance <= rightDistance
                right = !left
            }
        }

        if !up, !down {
            let upDistance = abs(mouse.y - observedRect.minY)
            let downDistance = abs(mouse.y - observedRect.maxY)
            if min(upDistance, downDistance) <= 96 {
                up = upDistance <= downDistance
                down = !up
            }
        }

        return ResizePredictionEdges(left: left, right: right, up: up, down: down)
    }
}
