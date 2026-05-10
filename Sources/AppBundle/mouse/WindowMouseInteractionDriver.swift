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

    private struct PendingResizeCandidate {
        let windowId: UInt32
        let baseRect: Rect
        let observedRect: Rect
        let edges: ResizeGestureEdges
        let mouseSample: MousePointerSample
    }

    private struct DragSourcePreviewState {
        let windowId: UInt32
        let subject: WindowDragSubject
        let anchorRect: Rect
        let mouseOffset: CGPoint
    }

    private var moveSession: MoveSession?
    private var resizeSession: ResizeSession?
    private var dragSourcePreviewState: DragSourcePreviewState?
    private var pendingResizeCandidate: PendingResizeCandidate?
    private var resizeGesture: ResizeGestureSessionState?
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
        let isNewSession = moveSession != session
        if isNewSession {
            WindowDragFrameGate.shared.reset(windowId: windowId)
        }
        moveSession = session
        if isNewSession {
            if subject == .group {
                WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
                if let sourceWindow = Window.get(byId: windowId) {
                    beginCompositedMovePreview(sourceWindow: sourceWindow, session: session)
                }
            } else if detachOrigin == .tabStrip {
                dragSourcePreviewState = nil
                WindowResizePreviewPanel.shared.endStableFrame()
                WindowResizePreviewPanel.shared.hide()
                WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
            } else {
                dragSourcePreviewState = nil
                WindowResizePreviewPanel.shared.endStableFrame()
                WindowResizePreviewPanel.shared.hide()
                WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
            }
        }
        startDisplayLoop()
        renderMoveFrame(force: isNewSession)
    }

    func startResize(windowId: UInt32) {
        let session = ResizeSession(windowId: windowId)
        if resizeSession != session {
            resizeGesture = nil
            isResizeSampleInFlight = false
            isMouseUpResetScheduled = false
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        setCurrentMouseManipulationKind(.resize)
        clearPendingWindowDragIntent()
        clearPendingUnmanagedWindowSnap()
        if let window = Window.get(byId: windowId) {
            let resizesTabGroup = window.nearestWindowTabGroup?.tabActiveWindow == window
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: !resizesTabGroup)
            if resizeGesture == nil {
                let sample = MousePointerTracker.shared.currentSample
                resizeGesture = makeResizeGesture(window: window, observedRect: window.lastKnownActualRect, sample: sample)
            }
            if let rect = resizeGesture?.predictedRect(mouse: MousePointerTracker.shared.currentSample.point) ??
                window.lastAppliedLayoutPhysicalRect ??
                window.lastKnownActualRect
            {
                beginStableResizePreviewFrame(for: window)
                updateCompositedResizePreview(window, rect: rect)
            }
        } else {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
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
            pendingResizeCandidate = nil
            resizeGesture = nil
            isResizeSampleInFlight = false
            WindowResizePreviewPanel.shared.endStableFrame()
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
        dragSourcePreviewState = nil
        pendingResizeCandidate = nil
        resizeGesture = nil
        isResizeSampleInFlight = false
        isMouseUpResetScheduled = false
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide()
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
    }

    func capturePendingResizeCandidate() async {
        guard config.enableWindowManagement,
              getCurrentMouseManipulationKind() == .none,
              let window = try? await getNativeFocusedWindow(),
              window.parent is TilingContainer,
              !window.isHiddenInCorner
        else {
            pendingResizeCandidate = nil
            return
        }
        let sample = MousePointerTracker.shared.currentSample
        let observedRect = (try? await window.getAxRect()) ?? window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
        guard let observedRect else {
            pendingResizeCandidate = nil
            return
        }
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        let edges = resizeGestureEdgesNear(mouse: sample.point, rect: observedRect, threshold: 96)
        guard edges.hasAny else {
            pendingResizeCandidate = nil
            return
        }
        pendingResizeCandidate = PendingResizeCandidate(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            edges: edges,
            mouseSample: sample,
        )
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
            WindowResizePreviewPanel.shared.endStableFrame()
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

        let currentMouseLocation = MousePointerTracker.shared.currentSample.point
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: currentMouseLocation)
        let shouldProcessFrame = WindowDragFrameGate.shared.shouldProcess(
            windowId: sourceWindow.windowId,
            point: currentMouseLocation,
            force: force,
        )
        guard shouldProcessFrame else { return }

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

    private func beginCompositedMovePreview(sourceWindow: Window, session: MoveSession) {
        guard session.subject == .group else {
            dragSourcePreviewState = nil
            WindowResizePreviewPanel.shared.endStableFrame()
            WindowResizePreviewPanel.shared.hide()
            return
        }
        guard let anchorRect = draggedWindowAnchorRect(for: sourceWindow.windowId) ??
            resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: session.subject),
            anchorRect.width > 0,
            anchorRect.height > 0
        else {
            dragSourcePreviewState = nil
            WindowResizePreviewPanel.shared.endStableFrame()
            WindowResizePreviewPanel.shared.hide()
            return
        }
        let mouseLocation = MousePointerTracker.shared.currentSample.point
        dragSourcePreviewState = DragSourcePreviewState(
            windowId: sourceWindow.windowId,
            subject: session.subject,
            anchorRect: anchorRect,
            mouseOffset: CGPoint(
                x: mouseLocation.x - anchorRect.topLeftX,
                y: mouseLocation.y - anchorRect.topLeftY,
            )
        )
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    }

    private func updateCompositedMovePreview(sourceWindow: Window, mouseLocation: CGPoint) {
        guard let state = dragSourcePreviewState,
              state.windowId == sourceWindow.windowId,
              state.subject == .group
        else { return }
        let frame = Rect(
            topLeftX: mouseLocation.x - state.mouseOffset.x,
            topLeftY: mouseLocation.y - state.mouseOffset.y,
            width: state.anchorRect.width,
            height: state.anchorRect.height,
        )
        guard let item = windowDragSourcePreviewItem(
            window: sourceWindow,
            subject: state.subject,
            frame: frame
        ) else { return }
        if let stableFrame = windowResizePreviewAllScreensFrame() {
            WindowResizePreviewPanel.shared.beginStableFrame(stableFrame)
        } else {
            WindowResizePreviewPanel.shared.endStableFrame()
        }
        WindowResizePreviewPanel.shared.show([item])
    }

    private func sampleResizeFrame(force: Bool) {
        guard let session = resizeSession else { return }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .resize else { return }
        guard let window = Window.get(byId: session.windowId) else {
            stop()
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == session.windowId {
            let rect = gesture.predictedRect(mouse: sample.point)
            gesture.latestRect = rect
            resizeGesture = gesture
            updateCompositedResizePreview(window, rect: rect)
            if force || sample.timestamp - gesture.lastCalibrationTimestamp >= 1.0 / 20.0 {
                calibrateResizeGesture(window: window, session: session, force: false)
            }
            return
        }

        guard force || !isResizeSampleInFlight else { return }
        calibrateResizeGesture(window: window, session: session, force: force)
    }

    private func finalResizeRect(for session: ResizeSession, window: Window) async -> Rect? {
        if let resizeGesture, resizeGesture.windowId == session.windowId {
            return resizeGesture.predictedRect(mouse: MousePointerTracker.shared.currentSample.point)
        }
        if let rect = try? await window.getAxRect() {
            return rect
        }
        if let resizeGesture, resizeGesture.windowId == session.windowId {
            return resizeGesture.latestRect
        }
        return window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
    }

    private func calibrateResizeGesture(window: Window, session: ResizeSession, force: Bool) {
        guard force || !isResizeSampleInFlight else { return }
        isResizeSampleInFlight = true
        let sessionWindowId = session.windowId
        let sample = MousePointerTracker.shared.currentSample
        Task { @MainActor in
            defer { isResizeSampleInFlight = false }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            guard let rect = try? await window.getAxRect() else { return }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            let freshSample = MousePointerTracker.shared.currentSample
            if var gesture = resizeGesture, gesture.windowId == sessionWindowId {
                gesture.calibrate(observedRect: rect, mouse: freshSample.point, timestamp: freshSample.timestamp)
                resizeGesture = gesture
                updateCompositedResizePreview(window, rect: gesture.predictedRect(mouse: freshSample.point))
            } else if let gesture = makeResizeGesture(window: window, observedRect: rect, sample: sample) {
                resizeGesture = gesture
                updateCompositedResizePreview(window, rect: gesture.predictedRect(mouse: freshSample.point))
            } else {
                updateCompositedResizePreview(window, rect: rect)
            }
        }
    }

    private func makeResizeGesture(window: Window, observedRect: Rect?, sample: MousePointerSample) -> ResizeGestureSessionState? {
        guard let observedRect = observedRect ?? window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return nil }
        if let pendingResizeCandidate,
           pendingResizeCandidate.windowId == window.windowId
        {
            return makeResizeGestureSession(
                windowId: window.windowId,
                baseRect: pendingResizeCandidate.baseRect,
                observedRect: pendingResizeCandidate.observedRect,
                mouse: pendingResizeCandidate.mouseSample.point,
                edges: pendingResizeCandidate.edges,
                timestamp: pendingResizeCandidate.mouseSample.timestamp,
            )
        }
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        return makeResizeGestureSession(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            mouse: sample.point,
            edges: resizeGestureEdges(baseRect: baseRect, observedRect: observedRect, mouse: sample.point),
            timestamp: sample.timestamp,
        )
    }

    private func beginStableResizePreviewFrame(for window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        WindowResizePreviewPanel.shared.beginStableFrame(workspace.workspaceMonitor.rect.toAppKitScreenRect)
    }
}
