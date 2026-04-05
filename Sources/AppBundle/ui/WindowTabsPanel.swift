import AppKit
import SwiftUI

private let windowTabStripPanelPrefix = "AeroSpace.windowTabs.strip."
private let windowTabDropPreviewPanelId = "AeroSpace.windowTabs.dropPreview"
private let windowDragCursorProxyPanelId = "AeroSpace.windowTabs.cursorProxy"
private let windowPreviewCornerAlphaThreshold: CGFloat = 0.3
private let windowPreviewCornerScanLimit = 48
private let windowTabDropPreviewTransitionDuration: TimeInterval = 0.12

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
    private var currentContent: WindowTabDropPreviewContent? = nil
    private var hasShownPreview = false

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowTabDropPreviewPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(_ preview: WindowTabDropPreviewViewModel) {
        let nextContent = WindowTabDropPreviewContent(model: preview)
        if currentContent != nextContent {
            hostingView.rootView = AnyView(WindowTabDropPreviewView(model: preview))
            currentContent = nextContent
        }
        let targetFrame = preview.frame.alignedToBackingPixels()
        if hasShownPreview {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = windowTabDropPreviewTransitionDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: true, animate: false)
            hasShownPreview = true
        }
        orderFrontRegardless()
    }

    func hide() {
        currentContent = nil
        hasShownPreview = false
        orderOut(nil)
    }
}

// MARK: - Cursor Drag Proxy (follows cursor during sidebar-originated drags)

@MainActor
final class WindowDragCursorProxyPanel: NSPanelHud {
    static let shared = WindowDragCursorProxyPanel()

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var currentLabel: String? = nil

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier(windowDragCursorProxyPanelId)
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func show(label: String, isGroup: Bool, mouseScreenPoint: CGPoint) {
        if currentLabel != label {
            hostingView.rootView = AnyView(WindowDragCursorProxyView(label: label, isGroup: isGroup))
            currentLabel = label
        }
        let proxyWidth: CGFloat = min(max(CGFloat(label.count) * 7 + 36, 80), 200)
        let proxyHeight: CGFloat = 28
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero

        // Default: right and below cursor
        var x = mouseScreenPoint.x + 14
        var y = mouseScreenPoint.y - proxyHeight - 6

        // Flip left if clipping right edge
        if x + proxyWidth > screenFrame.maxX {
            x = mouseScreenPoint.x - proxyWidth - 14
        }
        // Push up if clipping bottom edge
        if y < screenFrame.minY {
            y = mouseScreenPoint.y + 6
        }

        let frame = CGRect(x: x, y: y, width: proxyWidth, height: proxyHeight)
        setFrame(frame, display: true, animate: false)
        orderFrontRegardless()
    }

    func hide() {
        currentLabel = nil
        orderOut(nil)
    }
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

struct WindowTabDropPreviewViewModel: Equatable {
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

// MARK: - Constants

private let windowTabStripCornerRadius: CGFloat = 10
private let windowTabItemCornerRadius: CGFloat = 6
private let windowTabPreviewCornerRadius: CGFloat = 8

// MARK: - Tab Strip View (manages reorder drag state for all tabs)

private let tabReorderVerticalEscapeThreshold: CGFloat = 18

private struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel

    @State private var draggingTabId: UInt32? = nil
    @State private var dragTranslationX: CGFloat = 0
    @State private var hasCommittedToDetach = false

    var body: some View {
        let count = max(strip.tabs.count, 1)
        let stripWidth = strip.frame.width
        let tabWidth = max(120, min(220, (stripWidth - 12) / CGFloat(count)))
        let itemHeight = max(strip.frame.height - 6, 22)
        let effectiveTabWidth = tabWidth + 2 // include HStack spacing
        let stripCornerRadius = activeWindowTabStripCornerRadius

        let draggingIndex = draggingTabId.flatMap { id in strip.tabs.firstIndex(where: { $0.windowId == id }) }
        let targetIndex: Int? = draggingIndex.map { srcIdx in
            let delta = Int(round(dragTranslationX / effectiveTabWidth))
            return max(0, min(srcIdx + delta, strip.tabs.count - 1))
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(strip.tabs) { tab in
                    WindowTabItemView(
                        tab: tab,
                        width: tabWidth,
                        height: itemHeight,
                        isDragSource: draggingTabId == tab.windowId,
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
                                if hasCommittedToDetach {
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
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 3)
        .frame(width: stripWidth, height: strip.frame.height)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: stripCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: stripCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2),
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    if let activeTab = strip.tabs.first(where: \.isActive) ?? strip.tabs.first {
                        updateMoveFromTabStrip(activeTab.windowId)
                    }
                }
                .onEnded { _ in
                    finishMoveFromTabStrip()
                },
        )
    }

    @MainActor
    private var activeWindowTabStripCornerRadius: CGFloat {
        let activeWindowId = strip.tabs.first(where: \.isActive)?.windowId ?? strip.tabs.first?.windowId
        return activeWindowId.map(estimatedWindowPreviewCornerRadius) ?? windowTabStripCornerRadius
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
}

// MARK: - Tab Item View

private struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            guard !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
        } label: {
            Text(tab.title)
                .font(.system(size: 11, weight: tab.isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 6)
                .frame(width: width, height: height)
                .background(background)
        }
        .contentShape(RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous))
        .buttonStyle(.plain)
        .scaleEffect(isDragSource ? 1.05 : (isHovered ? 1.01 : 1.0))
        .opacity(isDragSource ? 0.75 : 1.0)
        .shadow(
            color: isDragSource ? Color.black.opacity(0.15) : Color.clear,
            radius: isDragSource ? 8 : 0,
            y: isDragSource ? 3 : 0,
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isDragSource)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Remove Tab From Stack") {
                removeWindowFromTabStrip(tab.windowId, fallbackWorkspace: tab.workspaceName)
            }
        }
    }

    private var foregroundColor: Color {
        if tab.isActive { return Color.primary }
        if isDragSource { return Color.primary }
        return isHovered ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.6)
    }

    @ViewBuilder
    private var background: some View {
        if isDragSource {
            RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        } else if isHovered, !tab.isActive {
            RoundedRectangle(cornerRadius: windowTabItemCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }
}

// MARK: - Drop Preview (visible fill + border)

private struct WindowTabDropPreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: WindowTabDropPreviewViewModel
    @State private var isPresented = false

    var body: some View {
        let cfg = borderConfig(for: model.style)
        let cornerRadius = model.referenceWindowId.map(estimatedWindowPreviewCornerRadius) ?? cfg.cornerRadius
        let shape = WindowTabDropOutlineShape(cornerRadii: model.geometry.cornerRadii(radius: cornerRadius))

        shape
            .fill(
                cfg.color.opacity(isPresented ? cfg.fillOpacity : 0),
            )
            .overlay {
                shape
                    .strokeBorder(
                        cfg.color.opacity(isPresented ? cfg.borderOpacity : 0.08),
                        style: cfg.strokeStyle,
                    )
            }
            .opacity(isPresented ? 1 : 0.82)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .compositingGroup()
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.12)) {
                    isPresented = true
                }
            }
    }

    private struct BorderConfig {
        let color: Color
        let cornerRadius: CGFloat
        let fillOpacity: Double
        let borderOpacity: Double
        let strokeStyle: StrokeStyle
    }

    private func borderConfig(for style: WindowTabDropPreviewStyle) -> BorderConfig {
        switch style {
            case .tabInsert:
                return BorderConfig(
                    color: .accentColor,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.08,
                    borderOpacity: 1,
                    strokeStyle: StrokeStyle(lineWidth: 3),
                )
            case .detach:
                return BorderConfig(
                    color: .accentColor,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.08,
                    borderOpacity: 1,
                    strokeStyle: StrokeStyle(lineWidth: 3),
                )
            case .stackSplit:
                return BorderConfig(
                    color: .accentColor,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.08,
                    borderOpacity: 1,
                    strokeStyle: StrokeStyle(lineWidth: 3),
                )
            case .swap:
                return BorderConfig(
                    color: .accentColor,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.08,
                    borderOpacity: 1,
                    strokeStyle: StrokeStyle(lineWidth: 3, dash: [8, 4]),
                )
            case .workspaceMove:
                return BorderConfig(
                    color: .accentColor,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.08,
                    borderOpacity: 1,
                    strokeStyle: StrokeStyle(lineWidth: 3),
                )
            case .sidebarWorkspaceMove:
                return BorderConfig(
                    color: .accentColor,
                    cornerRadius: windowTabPreviewCornerRadius,
                    fillOpacity: 0.08,
                    borderOpacity: 1,
                    strokeStyle: StrokeStyle(lineWidth: 3),
                )
        }
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
    let cornerRadii: PreviewCornerRadii
    var insetAmount: CGFloat = 0

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
    fileprivate func alignedToBackingPixels() -> CGRect {
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
