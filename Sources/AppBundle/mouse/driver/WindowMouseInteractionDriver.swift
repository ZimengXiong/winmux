import AppKit
import Common

let resizeGestureCalibrationInterval: TimeInterval = 1.0 / 30.0
let resizePreviewVisibleChangeThreshold = CGFloat(0.5)
private let shakeToggleCooldown: TimeInterval = 1.25

@MainActor
final class WindowMouseInteractionDriver {
    static let shared = WindowMouseInteractionDriver()

    struct MoveSession: Equatable {
        let windowId: UInt32
        let subject: WindowDragSubject
        let detachOrigin: TabDetachOrigin
        let startedInSidebar: Bool
    }

    struct ResizeSession: Equatable {
        let windowId: UInt32
    }

    struct PendingResizeCandidate {
        let windowId: UInt32
        let baseRect: Rect
        let observedRect: Rect
        let edges: ResizeGestureEdges
        let mouseSample: MousePointerSample
    }

    struct DragSourcePreviewState {
        let windowId: UInt32
        let subject: WindowDragSubject
        let anchorRect: Rect
        let mouseOffset: CGPoint
    }

    var moveSession: MoveSession?
    var resizeSession: ResizeSession?
    var dragSourcePreviewState: DragSourcePreviewState?
    var pendingResizeCandidate: PendingResizeCandidate?
    var resizeGesture: ResizeGestureSessionState?
    var isResizeSampleInFlight = false
    var isMouseUpResetScheduled = false
    var lastRenderedResizePreviewRect: Rect?
    var shakeGesture: WindowShakeGestureRecognizer?
    var didToggleLayoutWithShake = false
    var lastShakeToggleTimestampByWindowId: [UInt32: TimeInterval] = [:]
    var shakeTilingPlacementByWindowId: [UInt32: WindowShakeTilingPlacement] = [:]

    private init() {}
}

extension WindowMouseInteractionDriver {
    func startDisplayLoop() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.displayFrame()
        }
    }

    func displayFrame() {
        guard isLeftMouseButtonDown else {
            finishAfterMissedMouseUpIfNeeded()
            return
        }
        renderMoveFrame(force: false)
        sampleResizeFrame(force: false)
    }

    func finishAfterMissedMouseUpIfNeeded() {
        guard resizeSession != nil || moveSession != nil else {
            logWindowDragLive("resizePreview hide requested reason=displayLoop.idle mouseDown=\(isLeftMouseButtonDown)")
            DisplayRefreshDriver.shared.remove(owner: self)
            WindowResizePreviewPanel.shared.endStableFrame()
            WindowResizePreviewPanel.shared.hide(reason: "displayLoop.idle")
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
}

extension WindowMouseInteractionDriver {
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
        defer { finishResizeFlush(session: resizeSession) }
        guard let window = Window.get(byId: resizeSession.windowId) else { return }
        guard let rect = await finalResizeRect(for: resizeSession, window: window) else { return }
        guard self.resizeSession == resizeSession else { return }
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
        applyResizeWithMouse(window, rect: rect)
    }

    func stop() {
        logWindowDragLive("driver.stop moveSession=\(String(describing: moveSession)) resizeSession=\(String(describing: resizeSession)) manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil") kind=\(getCurrentMouseManipulationKind()) mouseDown=\(isLeftMouseButtonDown)")
        DisplayRefreshDriver.shared.remove(owner: self)
        moveSession = nil
        resizeSession = nil
        dragSourcePreviewState = nil
        pendingResizeCandidate = nil
        shakeGesture = nil
        didToggleLayoutWithShake = false
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.stop")
        WindowMouseInteractionOpacityController.shared.restore()
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
    }

    func finishResizeFlush(session: ResizeSession) {
        if resizeSession == session {
            resizeSession = nil
        }
        pendingResizeCandidate = nil
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.finishResizeFlush")
    }
}

extension WindowMouseInteractionDriver {
    func beginCompositedMovePreview(sourceWindow: Window, session: MoveSession) {
        guard session.subject == .group else {
            clearMovePreview()
            return
        }
        guard let anchorRect = draggedWindowAnchorRect(for: sourceWindow.windowId) ??
            resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: session.subject),
            anchorRect.width > 0,
            anchorRect.height > 0
        else {
            clearMovePreview()
            return
        }
        let mouseLocation = MousePointerTracker.shared.currentSample.point
        dragSourcePreviewState = DragSourcePreviewState(
            windowId: sourceWindow.windowId,
            subject: session.subject,
            anchorRect: anchorRect,
            mouseOffset: CGPoint(x: mouseLocation.x - anchorRect.topLeftX, y: mouseLocation.y - anchorRect.topLeftY)
        )
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    }

    func updateCompositedMovePreview(sourceWindow: Window, mouseLocation: CGPoint) {
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
        guard let item = windowDragSourcePreviewItem(window: sourceWindow, subject: state.subject, frame: frame)
        else { return }
        if let stableFrame = windowResizePreviewAllScreensFrame() {
            WindowResizePreviewPanel.shared.beginStableFrame(stableFrame)
        } else {
            WindowResizePreviewPanel.shared.endStableFrame()
        }
        WindowResizePreviewPanel.shared.show([item])
    }
}

extension WindowMouseInteractionDriver {
    func renderMoveFrame(force: Bool) {
        guard let session = moveSession else { return }
        guard (isLeftMouseButtonDown || force), getCurrentMouseManipulationKind() == .move else { return }
        guard currentlyManipulatedWithMouseWindowId == session.windowId,
              let sourceWindow = Window.get(byId: session.windowId)
        else {
            clearPendingWindowDragIntent()
            stop()
            return
        }

        let mouse = MousePointerTracker.shared.currentSample.point
        detectShakeIfNeeded(sourceWindow: sourceWindow, session: session)
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouse)
        let isPointerInsideSidebar = WorkspaceSidebarPanel.panel(containing: mouse) != nil
        let shouldProcess = session.startedInSidebar || isPointerInsideSidebar || WindowDragFrameGate.shared.shouldProcess(
            windowId: sourceWindow.windowId,
            point: mouse,
            force: force,
        )
        let gateState = WindowDragFrameGate.shared.state(for: sourceWindow.windowId)
        logWindowDragHitTestIfNeeded(
            signature: "drag-live:frame:window=\(sourceWindow.windowId):bucket=\(debugDescribeDragPointBucket(mouse)):process=\(shouldProcess):settled=\(gateState?.isSettled.description ?? "nil")",
            "[drag-live] frame window=\(sourceWindow.windowId) subject=\(debugDescribe(session.subject)) origin=\(session.detachOrigin) mouse=\(debugDescribe(mouse)) bucket=\(debugDescribeDragPointBucket(mouse)) shouldProcess=\(shouldProcess) velocity=\(gateState?.velocity.description ?? "nil") settled=\(gateState?.isSettled.description ?? "nil") force=\(force)"
        )
        guard shouldProcess else { return }

        renderManagedMoveFrame(sourceWindow: sourceWindow, mouseLocation: mouse, session: session)
    }

    func renderManagedMoveFrame(sourceWindow: Window, mouseLocation: CGPoint, session: MoveSession) {
        if didToggleLayoutWithShake {
            clearPendingWindowDragIntent()
            if sourceWindow.isFloating {
                moveFloatingWindowWithMouse(sourceWindow)
            }
            return
        }
        if WorkspaceSidebarPanel.panel(containing: mouseLocation) != nil {
            _ = updatePendingWindowDragIntent(
                sourceWindow: sourceWindow,
                mouseLocation: mouseLocation,
                subject: session.subject,
                detachOrigin: session.detachOrigin,
            )
            return
        }
        if session.startedInSidebar {
            refreshActiveWorkspaceSidebarDragPreviewIfNeeded()
            _ = updatePendingWindowDragIntent(
                sourceWindow: sourceWindow,
                mouseLocation: mouseLocation,
                subject: session.subject,
                detachOrigin: session.detachOrigin,
            )
            return
        }
        switch sourceWindow.parent?.cases {
            case .workspace:
                moveFloatingWindowWithMouse(sourceWindow)
            case .tilingContainer:
                _ = updatePendingWindowDragIntent(
                    sourceWindow: sourceWindow,
                    mouseLocation: mouseLocation,
                    subject: session.subject,
                    detachOrigin: session.detachOrigin,
                )
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer, nil:
                clearPendingWindowDragIntent()
        }
    }
}

extension WindowMouseInteractionDriver {
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
            shakeGesture = WindowShakeGestureRecognizer()
            didToggleLayoutWithShake = false
        }
        moveSession = session
        if shouldHideOtherWindowsDuringMove(session: session) {
            WindowMouseInteractionOpacityController.shared.update(
                activeWindowId: windowId,
                hidesPassiveTabGroupChrome: false,
            )
        } else {
            WindowMouseInteractionOpacityController.shared.restore()
        }
        if isNewSession {
            configureMoveChrome(windowId: windowId, session: session)
        }
        startDisplayLoop()
        renderMoveFrame(force: isNewSession)
    }

    func shouldHideOtherWindowsDuringMove(session: MoveSession) -> Bool {
        false
    }

    func configureMoveChrome(windowId: UInt32, session: MoveSession) {
        if session.startedInSidebar {
            clearMovePreview()
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        } else if shouldShowCompositedGroupMovePreview(session: session) {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
            if let sourceWindow = Window.get(byId: windowId) {
                beginCompositedMovePreview(sourceWindow: sourceWindow, session: session)
            }
        } else if session.detachOrigin == .tabStrip {
            clearMovePreview()
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        } else {
            clearMovePreview()
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        }
    }

    func clearMovePreview() {
        dragSourcePreviewState = nil
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "moveStart.clearMovePreview")
    }
}

extension WindowMouseInteractionDriver {
    func detectShakeIfNeeded(sourceWindow: Window, session: MoveSession) {
        guard config.enableShakeToToggleTiling,
              !didToggleLayoutWithShake,
              shouldRecognizeWindowShake(
                  kind: getCurrentMouseManipulationKind(),
                  subject: session.subject,
                  detachOrigin: session.detachOrigin,
                  startedInSidebar: session.startedInSidebar,
                  isPointerInsideSidebar: WorkspaceSidebarPanel.panel(
                      containing: MousePointerTracker.shared.currentSample.point
                  ) != nil,
              ),
              var gesture = shakeGesture
        else { return }
        let sample = MousePointerTracker.shared.currentSample
        guard gesture.observe(sample) else {
            shakeGesture = gesture
            return
        }
        shakeGesture = gesture
        let previousToggle = lastShakeToggleTimestampByWindowId[sourceWindow.windowId] ?? -.infinity
        guard sample.timestamp - previousToggle >= shakeToggleCooldown else { return }

        clearPendingWindowDragIntent()
        toggleFloatingForShake(sourceWindow)
        lastShakeToggleTimestampByWindowId[sourceWindow.windowId] = sample.timestamp
        didToggleLayoutWithShake = true
    }

    func toggleFloatingForShake(_ window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        if window.isFloating {
            if let placement = shakeTilingPlacementByWindowId.removeValue(forKey: window.windowId),
               let parent = placement.parent,
               parent.isBound,
               parent.nodeWorkspace === workspace
            {
                window.bind(
                    to: parent,
                    adaptiveWeight: placement.adaptiveWeight,
                    index: min(placement.index, parent.children.count),
                )
            } else {
                let placement = bindingDataForNewTilingWindow(workspace, window: window)
                window.bind(to: placement.parent, adaptiveWeight: placement.adaptiveWeight, index: placement.index)
            }
        } else {
            window.lastFloatingSize = window.lastKnownActualRect?.size ??
                window.lastAppliedLayoutPhysicalRect?.size ??
                window.lastFloatingSize
            if let placement = window.bindAsFloatingWindow(to: workspace) {
                shakeTilingPlacementByWindowId[window.windowId] = WindowShakeTilingPlacement(placement)
            }
        }
        window.lastAppliedLayoutPhysicalRect = nil
    }
}

extension WindowMouseInteractionDriver {
    func calibrateResizeGesture(window: Window, session: ResizeSession, force: Bool) {
        guard force || !isResizeSampleInFlight else { return }
        isResizeSampleInFlight = true
        let sessionWindowId = session.windowId
        let sample = MousePointerTracker.shared.currentSample
        Task { @MainActor in
            defer { isResizeSampleInFlight = false }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            guard let rect = try? await window.getAxRect() else { return }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            updateCalibratedResizeGesture(
                window: window,
                rect: rect,
                sessionWindowId: sessionWindowId,
                initialSample: sample,
            )
        }
    }

    func updateCalibratedResizeGesture(
        window: Window,
        rect: Rect,
        sessionWindowId: UInt32,
        initialSample: MousePointerSample,
    ) {
        let freshSample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == sessionWindowId {
            gesture.calibrate(observedRect: rect, mouse: freshSample.point, timestamp: freshSample.timestamp)
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: gesture.predictedRect(mouse: freshSample.point))
        } else if let gesture = makeResizeGesture(window: window, observedRect: rect, sample: initialSample) {
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: gesture.predictedRect(mouse: freshSample.point), force: true)
        } else {
            updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
        }
    }
}

extension WindowMouseInteractionDriver {
    func makePendingResizeCandidate() async -> PendingResizeCandidate? {
        // The candidate is best-effort calibration data: makeResizeGesture discards it unless
        // its windowId matches the window that actually reports resize events (which is
        // re-verified live there). So the logical focus is good enough here, and it avoids a
        // getNativeFocusedWindow AX round-trip to the focused app on every single left click.
        guard getCurrentMouseManipulationKind() == .none,
              let window = focus.windowOrNil,
              window.parent is TilingContainer,
              !window.isHiddenInCorner
        else { return nil }
        let sample = MousePointerTracker.shared.currentSample
        guard cachedResizeCandidateIsViable(window: window, sample: sample) else { return nil }
        let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
        guard let observedRect = (try? await window.getAxRect()) ?? cachedRect else { return nil }
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        let edges = resizeGestureCandidateEdges(mouse: sample.point, rect: observedRect)
        guard edges.hasAny else { return nil }
        return PendingResizeCandidate(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            edges: edges,
            mouseSample: sample,
        )
    }

    func cachedResizeCandidateIsViable(window: Window, sample: MousePointerSample) -> Bool {
        guard let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return true }
        return resizeGestureCandidateEdges(mouse: sample.point, rect: cachedRect).hasAny
    }
}

extension WindowMouseInteractionDriver {
    func capturePendingResizeCandidate() async {
        guard let candidate = await makePendingResizeCandidate() else {
            pendingResizeCandidate = nil
            return
        }
        pendingResizeCandidate = candidate
    }

    func makeResizeGesture(window: Window, observedRect: Rect?, sample: MousePointerSample) -> ResizeGestureSessionState? {
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
        return makeResizeGestureFromObservedRect(window: window, observedRect: observedRect, sample: sample)
    }

    func makeResizeGestureFromObservedRect(
        window: Window,
        observedRect: Rect,
        sample: MousePointerSample,
    ) -> ResizeGestureSessionState? {
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
}

extension WindowMouseInteractionDriver {
    func beginStableResizePreviewFrame(for window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        WindowResizePreviewPanel.shared.beginStableFrame(workspace.workspaceMonitor.rect.toAppKitScreenRect)
    }

    func updateResizePreviewIfNeeded(window: Window, rect: Rect, force: Bool = false) {
        guard force || resizePreviewHasVisibleChange(from: lastRenderedResizePreviewRect, to: rect) else { return }
        lastRenderedResizePreviewRect = rect
        updateCompositedResizePreview(window, rect: rect)
    }
}

func resizePreviewHasVisibleChange(from previous: Rect?, to next: Rect) -> Bool {
    guard let previous else { return true }
    return abs(previous.topLeftX - next.topLeftX) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.topLeftY - next.topLeftY) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.width - next.width) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.height - next.height) >= resizePreviewVisibleChangeThreshold
}

extension WindowMouseInteractionDriver {
    func sampleResizeFrame(force: Bool) {
        guard let session = resizeSession else {
            logWindowDragLive("resize.sample skipped reason=no-session force=\(force) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
            return
        }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .resize else {
            logWindowDragLive("resize.sample skipped reason=inactive session=\(session.windowId) force=\(force) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
            return
        }
        guard let window = Window.get(byId: session.windowId) else {
            logWindowDragLive("resize.sample missing-window session=\(session.windowId); stopping driver")
            stop()
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == session.windowId {
            let rect = gesture.predictedRect(mouse: sample.point)
            logWindowDragLive("resize.sample predicted session=\(session.windowId) force=\(force) mouse=\(debugDescribe(sample.point)) rect=\(debugDescribe(rect))")
            gesture.latestRect = rect
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: rect, force: force)
            if force || sample.timestamp - gesture.lastCalibrationTimestamp >= resizeGestureCalibrationInterval {
                calibrateResizeGesture(window: window, session: session, force: false)
            }
            return
        }

        guard force || !isResizeSampleInFlight else {
            logWindowDragLive("resize.sample skipped reason=calibration-in-flight session=\(session.windowId)")
            return
        }
        logWindowDragLive("resize.sample calibrating session=\(session.windowId) force=\(force)")
        calibrateResizeGesture(window: window, session: session, force: force)
    }

    func finalResizeRect(for session: ResizeSession, window: Window) async -> Rect? {
        if let rect = try? await window.getAxRect() {
            return rect
        }
        if let resizeGesture, resizeGesture.windowId == session.windowId {
            return resizeGesture.predictedRect(mouse: MousePointerTracker.shared.currentSample.point)
        }
        return window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
    }
}

extension WindowMouseInteractionDriver {
    func startResize(windowId: UInt32) {
        let session = ResizeSession(windowId: windowId)
        let isNewSession = resizeSession != session
        logWindowDragLive("resize.start window=\(windowId) isNewSession=\(isNewSession) existingSession=\(String(describing: resizeSession)) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
        if isNewSession {
            resetResizeTrackingState()
            clearPendingWindowDragIntent()
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        WindowMouseInteractionOpacityController.shared.update(
            activeWindowId: windowId,
            hidesPassiveTabGroupChrome: true,
        )
        setCurrentMouseManipulationKind(.resize)
        configureResizeChrome(windowId: windowId)
        startDisplayLoop()
        sampleResizeFrame(force: true)
    }

    func configureResizeChrome(windowId: UInt32) {
        guard let window = Window.get(byId: windowId) else {
            logWindowDragLive("resize.configureChrome missing-window window=\(windowId)")
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
            return
        }
        let resizesTabGroup = windowResizeUsesActiveTabGroupChrome(window: window)
        logWindowDragLive("resize.configureChrome window=\(windowId) resizesTabGroup=\(resizesTabGroup) lastKnown=\(debugDescribe(window.lastKnownActualRect)) lastApplied=\(debugDescribe(window.lastAppliedLayoutPhysicalRect))")
        if resizesTabGroup {
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        } else {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: true)
        }
        if resizeGesture == nil {
            let sample = MousePointerTracker.shared.currentSample
            resizeGesture = makeResizeGesture(window: window, observedRect: window.lastKnownActualRect, sample: sample)
        }
        guard let rect = resizeGesture?.predictedRect(mouse: MousePointerTracker.shared.currentSample.point) ??
            window.lastAppliedLayoutPhysicalRect ??
            window.lastKnownActualRect
        else { return }
        beginStableResizePreviewFrame(for: window)
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
    }

    func resetResizeTrackingState() {
        resizeGesture = nil
        isResizeSampleInFlight = false
        isMouseUpResetScheduled = false
        lastRenderedResizePreviewRect = nil
    }
}
