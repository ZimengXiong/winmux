import AppKit
import SwiftUI

private let windowTabStripPanelPrefix = "WinMux.windowTabs.strip."
private let windowTabDropPreviewPanelId = "WinMux.windowTabs.dropPreview"
private let windowDragCursorProxyPanelId = "WinMux.windowTabs.cursorProxy"
private let windowPreviewCornerAlphaThreshold: CGFloat = 0.3
private let windowPreviewCornerScanLimit = 48
private let windowTabDropPreviewTransitionDuration: TimeInterval = 0.16
private let windowDragCursorProxyFollowInterval: TimeInterval = 1.0 / 60.0

@MainActor
var windowPreviewCornerRadiusCache: [UInt32: CGFloat] = [:]

@MainActor
func estimatedWindowPreviewCornerRadius(for windowId: UInt32) -> CGFloat {
    if let cached = windowPreviewCornerRadiusCache[windowId] {
        return cached
    }
    let resolvedRadius = estimateWindowPreviewCornerRadiusFromImage(windowId: windowId) ?? windowTabPreviewCornerRadius
    windowPreviewCornerRadiusCache[windowId] = resolvedRadius
    return resolvedRadius
}

private func estimateWindowPreviewCornerRadiusFromImage(windowId: UInt32) -> CGFloat? {
    guard let cgImage = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowId),
        [.boundsIgnoreFraming, .nominalResolution],
    ) else {
        return nil
    }
    return estimateTopCornerRadius(in: cgImage)
}

private func estimateTopCornerRadius(in image: CGImage) -> CGFloat? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let width = bitmap.pixelsWide
    let height = bitmap.pixelsHigh
    let maxScan = min(windowPreviewCornerScanLimit, width / 2, height / 2)
    guard maxScan > 0 else { return nil }

    func alphaAt(x: Int, yFromTop: Int) -> CGFloat {
        let bitmapY = height - 1 - yFromTop
        guard bitmapY >= 0,
              bitmapY < height,
              x >= 0,
              x < width
        else {
            return 0
        }
        return bitmap.colorAt(x: x, y: bitmapY)?.alphaComponent ?? 0
    }

    func leadingOpaqueInset(yFromTop: Int, leftToRight: Bool) -> Int? {
        for step in 0 ..< maxScan {
            let x = leftToRight ? step : width - 1 - step
            if alphaAt(x: x, yFromTop: yFromTop) > windowPreviewCornerAlphaThreshold {
                return step
            }
        }
        return nil
    }

    func trailingOpaqueInset(xFromEdge: Int, topToBottom: Bool) -> Int? {
        let x = topToBottom ? xFromEdge : width - 1 - xFromEdge
        for step in 0 ..< maxScan {
            if alphaAt(x: x, yFromTop: step) > windowPreviewCornerAlphaThreshold {
                return step
            }
        }
        return nil
    }

    let samples = [
        leadingOpaqueInset(yFromTop: 0, leftToRight: true),
        leadingOpaqueInset(yFromTop: 0, leftToRight: false),
        trailingOpaqueInset(xFromEdge: 0, topToBottom: true),
        trailingOpaqueInset(xFromEdge: 0, topToBottom: false),
    ].compactMap { $0 }

    guard !samples.isEmpty else { return nil }
    return CGFloat(samples.max() ?? 0)
}

@MainActor
final class WindowTabStripPanelController {
    static let shared = WindowTabStripPanelController()

    private var panels: [ObjectIdentifier: WindowTabStripPanel] = [:]

    private init() {}

    func refresh() {
        guard TrayMenuModel.shared.isEnabled, config.windowTabs.enabled else {
            hideAll()
            return
        }

        let strips = TrayMenuModel.shared.windowTabStrips
        let activeIds = Set(strips.map(\.id))
        for strip in strips {
            let panel = panels[strip.id] ?? WindowTabStripPanel(id: strip.id)
            panels[strip.id] = panel
            panel.update(with: strip)
        }
        for staleId in panels.keys where !activeIds.contains(staleId) {
            panels[staleId]?.orderOut(nil)
            panels.removeValue(forKey: staleId)
        }
    }

    func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func setIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        for panel in panels.values {
            panel.ignoresMouseEvents = ignoresMouseEvents
        }
    }
}

@MainActor
private final class WindowTabStripPanel: NSPanelHud {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowTabStripContent? = nil

    init(id: ObjectIdentifier) {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabStripPanelPrefix + String(id.hashValue))
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func update(with strip: WindowTabStripViewModel) {
        let nextContent = WindowTabStripContent(strip: strip)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowTabStripView(strip: strip))
            currentContent = nextContent
        }
        debugFocusLog("WindowTabStripPanel.update id=\(String(describing: identifier?.rawValue)) frame=\(strip.frame)")
        setFrame(strip.frame, display: true, animate: false)
        ignoresMouseEvents = currentlyManipulatedWithMouseWindowId != nil
        orderFrontRegardless()
    }
}

private struct WindowTabStripContent: Equatable {
    let workspaceName: String
    let frame: CGRect
    let tabs: [WindowTabItemViewModel]

    init(strip: WindowTabStripViewModel) {
        workspaceName = strip.workspaceName
        frame = strip.frame
        tabs = strip.tabs
    }
}

@MainActor
final class WindowTabDropPreviewPanel: NSPanelHud {
    static let shared = WindowTabDropPreviewPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private let state = WindowTabDropPreviewState()
    private var currentContent: WindowTabDropPreviewContent? = nil
    private var hasShownPreview = false
    private var pendingHide: DispatchWorkItem? = nil
    private let hideDebounce: TimeInterval = 0.07

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabDropPreviewPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        // Keep the drop preview above actively dragged app windows.
        level = .statusBar
        contentView = hostingView
        hostingView.rootView = AnyView(WindowTabDropPreviewView(state: state))
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(_ preview: WindowTabDropPreviewViewModel) {
        pendingHide?.cancel()
        pendingHide = nil
        let nextContent = WindowTabDropPreviewContent(model: preview)
        let didChangeContent = currentContent != nextContent
        if didChangeContent {
            currentContent = nextContent
        }
        state.model = preview
        let targetFrame = preview.containerFrame.alignedToBackingPixels()
        if hasShownPreview {
            if didChangeContent {
                alphaValue = 0.92
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = windowTabDropPreviewTransitionDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(targetFrame, display: true)
                animator().alphaValue = 1
            }
        } else {
            setFrame(targetFrame, display: true, animate: false)
            alphaValue = 1
            hasShownPreview = true
        }
        orderFrontRegardless()
    }

    func hide() {
        pendingHide?.cancel()
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            self.state.model = nil
            self.currentContent = nil
            self.hasShownPreview = false
            self.alphaValue = 1
            self.orderOut(nil)
        }
        pendingHide = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDebounce, execute: hideWorkItem)
    }
}

// MARK: - Cursor Drag Proxy (follows cursor during sidebar-originated drags)

@MainActor
final class WindowDragCursorProxyPanel: NSPanelHud {
    static let shared = WindowDragCursorProxyPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentContent: WindowDragCursorProxyContent? = nil
    private var followMouseTimer: Timer? = nil
    private var proxySize: CGSize = .zero

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowDragCursorProxyPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(label: String, isGroup: Bool, mouseScreenPoint: CGPoint) {
        let nextContent = WindowDragCursorProxyContent(label: label, isGroup: isGroup)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
            currentContent = nextContent
        }
        proxySize = CGSize(
            width: min(max(CGFloat(label.count) * 7 + 36, 80), 200),
            height: 28,
        )
        updateFrame(mouseScreenPoint: mouseScreenPoint)
        startFollowingMouseIfNeeded()
        orderFrontRegardless()
    }

    func hide() {
        stopFollowingMouse()
        currentContent = nil
        orderOut(nil)
    }

    private func startFollowingMouseIfNeeded() {
        guard followMouseTimer == nil else { return }
        let timer = Timer(timeInterval: windowDragCursorProxyFollowInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFrame(mouseScreenPoint: NSEvent.mouseLocation)
            }
        }
        followMouseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopFollowingMouse() {
        followMouseTimer?.invalidate()
        followMouseTimer = nil
    }

    private func updateFrame(mouseScreenPoint: CGPoint) {
        guard proxySize.width > 0, proxySize.height > 0 else { return }
        let targetFrame = windowDragCursorProxyFrame(
            mouseScreenPoint: mouseScreenPoint,
            proxySize: proxySize,
        )
        if frame.size == targetFrame.size {
            setFrameOrigin(targetFrame.origin)
        } else {
            setFrame(targetFrame, display: false, animate: false)
        }
    }
}

private struct WindowDragCursorProxyContent: Equatable {
    let label: String
    let isGroup: Bool
}

private func windowDragCursorProxyFrame(mouseScreenPoint: CGPoint, proxySize: CGSize) -> CGRect {
    let screenFrame = NSScreen.screens
        .first(where: { $0.frame.contains(mouseScreenPoint) })?
        .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

    var x = mouseScreenPoint.x + 14
    var y = mouseScreenPoint.y - proxySize.height - 6

    if x + proxySize.width > screenFrame.maxX {
        x = mouseScreenPoint.x - proxySize.width - 14
    }
    if y < screenFrame.minY {
        y = mouseScreenPoint.y + 6
    }

    return CGRect(
        x: x,
        y: y,
        width: proxySize.width,
        height: proxySize.height,
    )
}

private struct WindowDragCursorProxyView: View {
    let label: String
    let isGroup: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGroup ? "square.stack" : "macwindow")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2),
        )
    }
}

private struct WindowTabDropPreviewContent: Equatable {
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isGroup: Bool

    init(model: WindowTabDropPreviewViewModel) {
        title = model.title
        subtitle = model.subtitle
        style = model.style
        geometry = model.geometry
        isGroup = model.isGroup
    }
}

@MainActor
private final class WindowTabDropPreviewState: ObservableObject {
    @Published var model: WindowTabDropPreviewViewModel? = nil
}

struct WindowTabDropPreviewViewModel: Equatable {
    let containerFrame: CGRect
    let frame: CGRect
    let title: String
    let subtitle: String
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isGroup: Bool
    let referenceWindowId: UInt32?
}

enum WindowTabDropPreviewStyle: Equatable {
    case tabInsert
    case detach
    case stackSplit
    case swap
    case workspaceMove
    case sidebarWorkspaceMove
}

enum WindowTabDropPreviewGeometry: Equatable {
    case rounded
    case tabStrip
    case splitLeft
    case splitRight
    case splitAbove
    case splitBelow

    fileprivate func cornerRadii(radius: CGFloat) -> PreviewCornerRadii {
        switch self {
            case .rounded:
                PreviewCornerRadii.uniform(radius)
            case .tabStrip:
                PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
            case .splitLeft:
                PreviewCornerRadii(topLeft: radius, topRight: 0, bottomRight: 0, bottomLeft: radius)
            case .splitRight:
                PreviewCornerRadii(topLeft: 0, topRight: radius, bottomRight: radius, bottomLeft: 0)
            case .splitAbove:
                PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: 0, bottomLeft: 0)
            case .splitBelow:
                PreviewCornerRadii(topLeft: 0, topRight: 0, bottomRight: radius, bottomLeft: radius)
        }
    }
}

@MainActor
private func focusWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  let liveFocus = window.toLiveFocusOrNil()
            else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            _ = setFocus(to: liveFocus)
            window.nativeFocus()
        }
    }
}

@MainActor
private func removeWindowFromTabStrip(_ windowId: UInt32, fallbackWorkspace: String) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId) else {
                _ = Workspace.existing(byName: fallbackWorkspace)?.focusWorkspace()
                return
            }
            _ = removeWindowFromTabStack(window)
            window.nativeFocus()
        }
    }
}

@MainActor
private func reorderTabInStrip(_ windowId: UInt32, toIndex targetIndex: Int) {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task {
        try await runLightSession(.menuBarButton, token) {
            guard let window = Window.get(byId: windowId),
                  let parent = window.parent as? TilingContainer,
                  parent.layout == .accordion,
                  let currentIndex = window.ownIndex
            else { return }
            let clampedTarget = max(0, min(targetIndex, parent.children.count - 1))
            guard clampedTarget != currentIndex else { return }
            let binding = window.unbindFromParent()
            window.bind(to: parent, adaptiveWeight: binding.adaptiveWeight, index: clampedTarget)
            window.markAsMostRecentChild()
            _ = window.focusWindow()
        }
    }
}

@MainActor
private func updateDetachedTabFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    _ = beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: .window,
        detachOrigin: .tabStrip,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: .window),
    )
    _ = updatePendingDetachedTabIntent(sourceWindow: window, mouseLocation: mouseLocation, origin: .tabStrip)
}

@MainActor
func shouldDeferWindowTabStripGroupDragToDetachedTabDrag() -> Bool {
    getCurrentMouseManipulationKind() == .move &&
        getCurrentMouseDragSubject() == .window &&
        getCurrentMouseTabDetachOrigin() == .tabStrip
}

func isWindowTabStripDragInProgress(
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
) -> Bool {
    guard kind == .move, !startedInSidebar else { return false }
    return detachOrigin == .tabStrip || subject == .group
}

@MainActor
func isWindowTabStripDragInProgress() -> Bool {
    isWindowTabStripDragInProgress(
        kind: getCurrentMouseManipulationKind(),
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

@MainActor
func shouldHandleWindowTabStripGroupDragEnd() -> Bool {
    !shouldDeferWindowTabStripGroupDragToDetachedTabDrag()
}

@MainActor
private func updateMoveFromTabStrip(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId) else {
        clearPendingWindowDragIntent()
        cancelManipulatedWithMouseState()
        return
    }
    if shouldDeferWindowTabStripGroupDragToDetachedTabDrag() {
        return
    }
    _ = beginWindowMoveWithMouseSessionIfNeeded(
        windowId: window.windowId,
        subject: .group,
        detachOrigin: .window,
        startedInSidebar: false,
        anchorRect: resolvedDraggedWindowAnchorRect(for: window, subject: .group),
    )
    _ = updatePendingWindowDragIntent(sourceWindow: window, mouseLocation: mouseLocation, subject: .group, detachOrigin: .window)
}

@MainActor
private func finishMoveFromTabStrip() {
    guard shouldHandleWindowTabStripGroupDragEnd() else { return }
    Task { @MainActor in
        try? await resetManipulatedWithMouseIfPossible()
    }
}

@MainActor
private func shouldPromoteTabStripDragToGroup(windowId: UInt32) -> Bool {
    if shouldContinueCurrentGroupDrag(windowId: windowId) {
        return true
    }
    guard let window = Window.get(byId: windowId) else { return false }
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    return shouldPromoteWindowDragToTabGroupDrag(
        isOptionPressed: isOptionPressed,
        isTabbedWindow: isWindowInDraggableTabGroup(window),
    )
}

@MainActor
private func shouldAllowTabStripChromeGroupDrag(windowId: UInt32) -> Bool {
    if shouldContinueCurrentGroupDrag(windowId: windowId) {
        return true
    }
    guard let window = Window.get(byId: windowId) else { return false }
    return isWindowInDraggableTabGroup(window)
}

// MARK: - Constants

private let windowTabPreviewCornerRadius: CGFloat = 8
private let windowTabStripContentHorizontalPadding: CGFloat = 2
private let windowTabStripGroupHandleWidth: CGFloat = 4
private let windowTabStripCornerRadius: CGFloat = 11
private let windowTabStripInnerCornerRadius: CGFloat = 8
private let windowTabStripTabSpacing: CGFloat = 4
private let windowTabActivePillAnimation: Animation = .easeOut(duration: 0.12)
private let windowIntentPreviewTint = Color(nsColor: .systemBlue)

func windowTabStripContentPadding() -> CGFloat {
    windowTabStripContentHorizontalPadding
}

func windowTabStripReservedGroupHandleWidth() -> CGFloat {
    windowTabStripGroupHandleWidth
}

func windowTabStripAvailableTabsWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        stripWidth
            - (windowTabStripReservedGroupHandleWidth() * 2)
            - (windowTabStripContentHorizontalPadding * 2),
    )
}

func windowTabStripTabWidth(stripWidth: CGFloat, count: Int) -> CGFloat {
    let effectiveCount = max(count, 1)
    return max(120, min(220, windowTabStripAvailableTabsWidth(stripWidth: stripWidth) / CGFloat(effectiveCount)))
}

// MARK: - Tab Strip View (manages reorder drag state for all tabs)

private let tabReorderVerticalEscapeThreshold: CGFloat = 18

private struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel

    @State private var draggingTabId: UInt32? = nil
    @State private var dragTranslationX: CGFloat = 0
    @State private var hasCommittedToDetach = false
    @Namespace private var activeTabNamespace

    var body: some View {
        let count = max(strip.tabs.count, 1)
        let stripWidth = strip.frame.width
        let tabWidth = windowTabStripTabWidth(stripWidth: stripWidth, count: count)
        let itemHeight = max(strip.frame.height - 10, 22)
        let effectiveTabWidth = tabWidth + windowTabStripTabSpacing
        let groupDragWindowId = strip.tabs.first(where: \.isActive)?.windowId ?? strip.tabs.first?.windowId

        let draggingIndex = draggingTabId.flatMap { id in strip.tabs.firstIndex(where: { $0.windowId == id }) }
        let targetIndex: Int? = draggingIndex.map { srcIdx in
            let delta = Int(round(dragTranslationX / effectiveTabWidth))
            return max(0, min(srcIdx + delta, strip.tabs.count - 1))
        }

        HStack(spacing: 0) {
            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: windowTabStripTabSpacing) {
                    ForEach(strip.tabs) { tab in
                        WindowTabItemView(
                            tab: tab,
                            width: tabWidth,
                            height: itemHeight,
                            isDragSource: draggingTabId == tab.windowId,
                            activeTabNamespace: activeTabNamespace,
                        )
                        .offset(x: tabVisualOffset(
                            for: tab,
                            draggingIndex: draggingIndex,
                            targetIndex: targetIndex,
                            effectiveTabWidth: effectiveTabWidth,
                        ))
                        .zIndex(draggingTabId == tab.windowId ? 1 : 0)
                        .shadow(
                            color: draggingTabId == tab.windowId ? Color.black.opacity(0.12) : Color.clear,
                            radius: draggingTabId == tab.windowId ? 6 : 0,
                            y: draggingTabId == tab.windowId ? 2 : 0,
                        )
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: targetIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if shouldPromoteTabStripDragToGroup(windowId: tab.windowId) {
                                        draggingTabId = nil
                                        dragTranslationX = 0
                                        hasCommittedToDetach = false
                                        updateMoveFromTabStrip(tab.windowId)
                                        return
                                    }
                                    if hasCommittedToDetach {
                                        updateDetachedTabFromTabStrip(tab.windowId)
                                        return
                                    }

                                    let dy = value.translation.height

                                    // If vertical drag exceeds threshold, commit to detach
                                    if abs(dy) > tabReorderVerticalEscapeThreshold, strip.tabs.count > 1 {
                                        hasCommittedToDetach = true
                                        draggingTabId = nil
                                        dragTranslationX = 0
                                        updateDetachedTabFromTabStrip(tab.windowId)
                                        return
                                    }

                                    draggingTabId = tab.windowId
                                    dragTranslationX = value.translation.width
                                }
                                .onEnded { _ in
                                    if shouldContinueCurrentGroupDrag(windowId: tab.windowId) {
                                        finishMoveFromTabStrip()
                                    } else if hasCommittedToDetach {
                                        hasCommittedToDetach = false
                                        Task { @MainActor in
                                            try? await resetManipulatedWithMouseIfPossible()
                                        }
                                    } else if let srcIdx = draggingIndex, let tgtIdx = targetIndex, srcIdx != tgtIdx {
                                        reorderTabInStrip(tab.windowId, toIndex: tgtIdx)
                                    }
                                    draggingTabId = nil
                                    dragTranslationX = 0
                                },
                        )
                    }
                }
                .padding(.horizontal, windowTabStripContentHorizontalPadding)
            }
            .frame(maxWidth: .infinity)
            .background {
                tabStripChromeButton(windowId: groupDragWindowId)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        guard let windowId = groupDragWindowId,
                              shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                        else { return }
                        updateMoveFromTabStrip(windowId)
                    }
                    .onEnded { _ in
                        guard let windowId = groupDragWindowId,
                              shouldContinueCurrentGroupDrag(windowId: windowId)
                        else { return }
                        finishMoveFromTabStrip()
                    },
            )

            WindowTabGroupHandleView(
                windowId: groupDragWindowId,
                workspaceName: strip.workspaceName
            )
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(width: stripWidth, height: strip.frame.height)
        .background {
            tabStripSurface
        }
        .overlay {
            RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(usesNativeLiquidGlass ? 0.10 : 0.13), lineWidth: 0.6)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.01),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    lineWidth: 0.5
                )
                .blendMode(.screen)
        }
        .shadow(
            color: Color.black.opacity(usesNativeLiquidGlass ? 0.08 : 0.14),
            radius: usesNativeLiquidGlass ? 1.5 : 4,
            y: 1
        )
        .clipShape(RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous))
        .animation(windowTabActivePillAnimation, value: strip.tabs.first(where: \.isActive)?.windowId)
    }

    private var tabStripSurface: some View {
        ZStack {
            liquidGlassBackground(
                in: RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous),
                isInteractive: true
            ) {
                RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                .fill(Color.black.opacity(usesNativeLiquidGlass ? 0.025 : 0.09))
            RoundedRectangle(cornerRadius: windowTabStripCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.025),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
        }
    }

    private func tabVisualOffset(
        for tab: WindowTabItemViewModel,
        draggingIndex: Int?,
        targetIndex: Int?,
        effectiveTabWidth: CGFloat,
    ) -> CGFloat {
        guard let draggingIndex, let targetIndex else {
            // Dragged tab follows cursor 1:1
            if tab.windowId == draggingTabId {
                return dragTranslationX
            }
            return 0
        }

        // The dragged tab follows the cursor directly
        if tab.windowId == draggingTabId {
            return dragTranslationX
        }

        guard let tabIndex = strip.tabs.firstIndex(where: { $0.id == tab.id }) else { return 0 }

        // Tabs between source and target shift to make room
        if draggingIndex < targetIndex {
            // Dragging right: tabs in (source, target] shift one slot left
            if tabIndex > draggingIndex, tabIndex <= targetIndex {
                return -effectiveTabWidth
            }
        } else if draggingIndex > targetIndex {
            // Dragging left: tabs in [target, source) shift one slot right
            if tabIndex >= targetIndex, tabIndex < draggingIndex {
                return effectiveTabWidth
            }
        }

        return 0
    }

    private func focusTabStripChrome(windowId: UInt32?) {
        guard let windowId, !isWindowTabStripDragInProgress() else { return }
        focusWindowFromTabStrip(windowId, fallbackWorkspace: strip.workspaceName)
    }

    private func tabStripChromeButton(windowId: UInt32?) -> some View {
        Button {
            focusTabStripChrome(windowId: windowId)
        } label: {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus Tab Group")
    }
}

private struct WindowTabGroupHandleView: View {
    let windowId: UInt32?
    let workspaceName: String

    var body: some View {
        Button {
            guard let windowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStrip(windowId, fallbackWorkspace: workspaceName)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus Tab Group")
        .frame(width: windowTabStripReservedGroupHandleWidth())
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    guard let windowId else { return }
                    updateMoveFromTabStrip(windowId)
                }
                .onEnded { _ in
                    finishMoveFromTabStrip()
                },
        )
    }
}

// MARK: - Tab Item View

private struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let activeTabNamespace: Namespace.ID

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                guard !isWindowTabStripDragInProgress() else { return }
                focusWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            } label: {
                HStack(spacing: 0) {
                    Text(tab.title)
                        .font(.system(size: 11, weight: tab.isActive ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(foregroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 9)
                .padding(.trailing, 27)
                .frame(width: width, height: height)
                .background(background)
                .contentShape(tabShape)
            }
            .buttonStyle(.plain)

            if showsRemoveControl {
                Button {
                    removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white.opacity(isHovered ? 0.82 : 0.66))
                        .frame(width: 18, height: 18)
                        .background {
                            Circle()
                                .fill(Color.black.opacity(0.18))
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Tab From Stack")
                .help("Remove Tab From Stack")
                .padding(.trailing, 5)
                .transition(.opacity.combined(with: .scale(scale: 0.84)))
            }
        }
        .contentShape(tabShape)
        .scaleEffect(isDragSource ? 1.04 : (isHovered ? 1.015 : 1.0))
        .opacity(isDragSource ? 0.75 : 1.0)
        .shadow(
            color: isDragSource ? Color.black.opacity(0.18) : Color.clear,
            radius: isDragSource ? 8 : 0,
            y: isDragSource ? 3 : 0
        )
        .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.78), value: isDragSource)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : windowTabActivePillAnimation, value: tab.isActive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsRemoveControl)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
    }

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
    }

    private var showsRemoveControl: Bool {
        isHovered || tab.isActive
    }

    private var foregroundColor: Color {
        if tab.isActive { return Color.white.opacity(0.98) }
        if isDragSource { return Color.white.opacity(0.94) }
        return isHovered ? Color.white.opacity(0.90) : Color.white.opacity(0.72)
    }

    @ViewBuilder
    private var background: some View {
        if isDragSource {
            tabShape
                .fill(Color.accentColor.opacity(0.20))
                .overlay {
                    tabShape
                        .strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.7)
                }
        } else if tab.isActive {
            tabShape
                .fill(Color.white.opacity(0.14))
                .overlay {
                    tabShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.055),
                                ],
                                startPoint: .top,
                                endPoint: .bottom,
                            ),
                        )
                }
                .overlay {
                    tabShape
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.6)
                }
                .matchedGeometryEffect(id: "window-tab-active-pill", in: activeTabNamespace)
        } else if isHovered, !tab.isActive {
            tabShape
                .fill(Color.white.opacity(0.07))
                .overlay {
                    tabShape
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Drop Preview (visible fill + border)

private struct WindowTabDropPreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: WindowTabDropPreviewState
    @State private var isPresented = false

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                if let model = state.model {
                    let cfg = borderConfig(for: model.style)
                    let cornerRadius = model.referenceWindowId.map(estimatedWindowPreviewCornerRadius) ?? cfg.cornerRadius
                    let shape = WindowTabDropOutlineShape(cornerRadii: model.geometry.cornerRadii(radius: cornerRadius))
                    let localFrame = localPreviewFrame(for: model)

                    previewSurface(shape: shape, config: cfg)
                        .frame(width: localFrame.width, height: localFrame.height)
                        .offset(x: localFrame.minX, y: localFrame.minY)
                    .opacity(isPresented ? 1 : 0.84)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            isPresented = state.model != nil
        }
        .onChange(of: state.model != nil) { isVisible in
            withAnimation(reduceMotion ? .easeOut(duration: 0.05) : .easeOut(duration: 0.07)) {
                isPresented = isVisible
            }
        }
    }

    private struct BorderConfig {
        let color: Color
        let cornerRadius: CGFloat
        let fillOpacity: Double
        let borderOpacity: Double
        let glowOpacity: Double
        let glowRadius: CGFloat
        let strokeStyle: StrokeStyle
    }

    private func borderConfig(for style: WindowTabDropPreviewStyle) -> BorderConfig {
        switch style {
            case .tabInsert:
                return BorderConfig(
                    color: windowIntentPreviewTint,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.20,
                    borderOpacity: 0.70,
                    glowOpacity: 0.18,
                    glowRadius: 10,
                    strokeStyle: StrokeStyle(lineWidth: 2.2),
                )
            case .detach:
                return BorderConfig(
                    color: windowIntentPreviewTint,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.18,
                    borderOpacity: 0.68,
                    glowOpacity: 0.16,
                    glowRadius: 10,
                    strokeStyle: StrokeStyle(lineWidth: 2.2),
                )
            case .stackSplit:
                return BorderConfig(
                    color: windowIntentPreviewTint,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.18,
                    borderOpacity: 0.68,
                    glowOpacity: 0.16,
                    glowRadius: 10,
                    strokeStyle: StrokeStyle(lineWidth: 2.2),
                )
            case .swap:
                return BorderConfig(
                    color: windowIntentPreviewTint,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.16,
                    borderOpacity: 0.68,
                    glowOpacity: 0.14,
                    glowRadius: 9,
                    strokeStyle: StrokeStyle(lineWidth: 2.2, dash: [7, 4]),
                )
            case .workspaceMove:
                return BorderConfig(
                    color: windowIntentPreviewTint,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.18,
                    borderOpacity: 0.68,
                    glowOpacity: 0.16,
                    glowRadius: 10,
                    strokeStyle: StrokeStyle(lineWidth: 2.2),
                )
            case .sidebarWorkspaceMove:
                return BorderConfig(
                    color: windowIntentPreviewTint,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.18,
                    borderOpacity: 0.68,
                    glowOpacity: 0.16,
                    glowRadius: 10,
                    strokeStyle: StrokeStyle(lineWidth: 2.2),
                )
        }
    }

    private func previewSurface(shape: WindowTabDropOutlineShape, config: BorderConfig) -> some View {
        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            shape
                .fill(Color.black.opacity(0.08))
            shape
                .fill(config.color.opacity(isPresented ? config.fillOpacity : 0))
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isPresented ? 0.13 : 0),
                            Color.white.opacity(isPresented ? 0.025 : 0),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .blendMode(.screen)
            shape
                .strokeBorder(Color.white.opacity(isPresented ? 0.18 : 0), lineWidth: 0.7)
            shape
                .strokeBorder(
                    config.color.opacity(isPresented ? config.borderOpacity : 0.10),
                    style: config.strokeStyle,
                )
        }
        .shadow(
            color: config.color.opacity(isPresented ? config.glowOpacity : 0),
            radius: isPresented ? config.glowRadius : 0
        )
    }

    private func localPreviewFrame(for model: WindowTabDropPreviewViewModel) -> CGRect {
        let localMinX = model.frame.minX - model.containerFrame.minX
        let localMinY = model.containerFrame.height - (model.frame.maxY - model.containerFrame.minY)
        return CGRect(
            x: localMinX,
            y: localMinY,
            width: model.frame.width,
            height: model.frame.height
        )
    }
}

private struct PreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> PreviewCornerRadii {
        PreviewCornerRadii(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }
}

private struct WindowTabDropOutlineShape: InsettableShape {
    var cornerRadii: PreviewCornerRadii
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cornerRadii.topLeft, cornerRadii.topRight),
                AnimatablePair(cornerRadii.bottomRight, cornerRadii.bottomLeft)
            )
        }
        set {
            cornerRadii = PreviewCornerRadii(
                topLeft: newValue.first.first,
                topRight: newValue.first.second,
                bottomRight: newValue.second.first,
                bottomLeft: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard !insetRect.isNull, insetRect.width > 0, insetRect.height > 0 else { return Path() }

        let maxRadius = min(insetRect.width, insetRect.height) / 2
        let tl = min(cornerRadii.topLeft, maxRadius)
        let tr = min(cornerRadii.topRight, maxRadius)
        let br = min(cornerRadii.bottomRight, maxRadius)
        let bl = min(cornerRadii.bottomLeft, maxRadius)

        var path = Path()
        path.move(to: CGPoint(x: insetRect.minX + tl, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.maxX - br, y: insetRect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false,
            )
        }
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: insetRect.minX + tl, y: insetRect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false,
            )
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> WindowTabDropOutlineShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

extension CGRect {
    func alignedToBackingPixels() -> CGRect {
        let scale = (NSScreen.screens
            .max(by: { $0.frame.intersection(self).area < $1.frame.intersection(self).area })?
            .backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let alignedMinX = (minX * scale).rounded() / scale
        let alignedMinY = (minY * scale).rounded() / scale
        let alignedMaxX = (maxX * scale).rounded() / scale
        let alignedMaxY = (maxY * scale).rounded() / scale
        return CGRect(
            x: alignedMinX,
            y: alignedMinY,
            width: max(alignedMaxX - alignedMinX, 0),
            height: max(alignedMaxY - alignedMinY, 0),
        )
    }

    fileprivate var area: CGFloat {
        isNull ? 0 : width * height
    }
}
