import AppKit
import Common
import SwiftUI

private let unmanagedSnapPreviewBorderWidth: CGFloat = 3
private let unmanagedSnapPreviewCornerRadius: CGFloat = 10
private let unmanagedSnapPreviewTransitionDuration: TimeInterval = 0.14
private func alignedUnmanagedSnapPreviewFrame(_ frame: CGRect) -> CGRect {
    let scale = (
        NSScreen.screens.max(by: { $0.frame.intersection(frame).width * $0.frame.intersection(frame).height <
            $1.frame.intersection(frame).width * $1.frame.intersection(frame).height
        })?.backingScaleFactor ??
            NSScreen.main?.backingScaleFactor ??
            2
    )
    let alignedMinX = (frame.minX * scale).rounded() / scale
    let alignedMinY = (frame.minY * scale).rounded() / scale
    let alignedMaxX = (frame.maxX * scale).rounded() / scale
    let alignedMaxY = (frame.maxY * scale).rounded() / scale
    return CGRect(
        x: alignedMinX,
        y: alignedMinY,
        width: max(alignedMaxX - alignedMinX, 0),
        height: max(alignedMaxY - alignedMinY, 0),
    )
}

@MainActor
final class UnmanagedWindowSnapPreviewPanel: NSPanelHud {
    static let shared = UnmanagedWindowSnapPreviewPanel()

    private let state = UnmanagedWindowSnapPreviewState()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var pendingHide: DispatchWorkItem? = nil
    private let hideDebounce: TimeInterval = 0.07
    private var hasShownPreview = false
    private var animationStartTime: CFTimeInterval = 0
    private var animationStartFrame: CGRect = .zero
    private var animationTargetFrame: CGRect = .zero

    override private init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier("unmanagedWindowSnapPreviewPanel")
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = true
        applyWinMuxLayer(.overlay)
        backgroundColor = .clear

        hostingView.rootView = AnyView(UnmanagedWindowSnapPreviewView(state: state))
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func show(action: UnmanagedWindowSnapAction, frame: CGRect) {
        pendingHide?.cancel()
        pendingHide = nil
        state.action = action
        let targetFrame = alignedUnmanagedSnapPreviewFrame(frame)
        if hasShownPreview {
            animateFrame(to: targetFrame, duration: unmanagedSnapPreviewTransitionDuration)
        } else {
            DisplayRefreshDriver.shared.remove(owner: self)
            setFrame(targetFrame, display: true, animate: false)
            hasShownPreview = true
        }
        orderFrontRegardless()
    }

    func hide() {
        pendingHide?.cancel()
        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            DisplayRefreshDriver.shared.remove(owner: self)
            self.hasShownPreview = false
            self.state.action = nil
            self.orderOut(nil)
        }
        pendingHide = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDebounce, execute: hideWorkItem)
    }

    private func animateFrame(to targetFrame: CGRect, duration: TimeInterval) {
        animationStartTime = CACurrentMediaTime()
        animationStartFrame = frame
        animationTargetFrame = targetFrame
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] timestamp in
            self?.updateFrameAnimation(timestamp: timestamp, duration: duration)
        }
    }

    private func updateFrameAnimation(timestamp: CFTimeInterval, duration: TimeInterval) {
        let rawProgress = duration > 0 ? CGFloat((timestamp - animationStartTime) / duration) : 1
        let progress = displayRefreshEaseInOut(rawProgress)
        let nextFrame = displayRefreshInterpolate(animationStartFrame, animationTargetFrame, progress: progress)
        setFrame(alignedUnmanagedSnapPreviewFrame(nextFrame), display: true, animate: false)
        guard rawProgress >= 1 else { return }
        setFrame(animationTargetFrame, display: true, animate: false)
        DisplayRefreshDriver.shared.remove(owner: self)
    }
}

@MainActor
private final class UnmanagedWindowSnapPreviewState: ObservableObject {
    @Published var action: UnmanagedWindowSnapAction? = nil
}

private struct UnmanagedWindowSnapPreviewView: View {
    @ObservedObject var state: UnmanagedWindowSnapPreviewState

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: unmanagedSnapPreviewCornerRadius, style: .continuous)
            let accent = Color(nsColor: .controlAccentColor)
            ZStack {
                LiquidGlassSurface(
                    shape: shape,
                    tint: accent,
                    tintOpacity: 0.14,
                    scrimOpacity: 0.11,
                    highlightOpacity: 0.14,
                    borderOpacity: 0.18,
                    glowOpacity: 0.18,
                    glowRadius: 14,
                    lineWidth: 0.8,
                    isInteractive: false,
                )
                shape
                    .strokeBorder(
                        accent.opacity(0.74),
                        style: StrokeStyle(lineWidth: unmanagedSnapPreviewBorderWidth, lineJoin: .round),
                    )
                unmanagedSnapPreviewGlyph(action: state.action, size: proxy.size)
            }
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    private func unmanagedSnapPreviewGlyph(action: UnmanagedWindowSnapAction?, size: CGSize) -> some View {
        let symbolName = unmanagedSnapPreviewSymbolName(for: action)
        let side = min(max(min(size.width, size.height) * 0.12, 34), 52)
        return Image(systemName: symbolName)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(width: side, height: side)
            .background {
                Circle()
                    .fill(Color.black.opacity(0.16))
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                    }
            }
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
    }

    private func unmanagedSnapPreviewSymbolName(for action: UnmanagedWindowSnapAction?) -> String {
        switch action {
            case .maximize:
                return "arrow.up.left.and.arrow.down.right"
            case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
                return "rectangle.split.3x1"
            case .topHalf, .bottomHalf:
                return "rectangle.split.1x2"
            case .leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight:
                return "rectangle.split.2x1"
            case nil:
                return "rectangle"
        }
    }
}
