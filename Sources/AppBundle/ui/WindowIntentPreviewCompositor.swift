import AppKit
import Common
import SwiftUI

@MainActor
final class WindowIntentPreviewCompositorView: NSView {
    let surfaceLayer = CAShapeLayer()
    let highlightLayer = CAShapeLayer()
    let innerStrokeLayer = CAShapeLayer()
    let accentStrokeLayer = CAShapeLayer()
    let activeStrokeLayer = CAShapeLayer()
    let guideLayer = CAShapeLayer()
    let activeGuideLayer = CAShapeLayer()
    var currentModel: WindowTabDropPreviewViewModel?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let backingLayer = CALayer()
        backingLayer.masksToBounds = false
        backingLayer.isGeometryFlipped = true
        layer = backingLayer
        configureLayers(backingLayer)

        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ model: WindowTabDropPreviewViewModel, animation: WindowIntentPreviewAnimation) {
        currentModel = model
        isHidden = false
        render(model, animation: animation)
    }

    func clear() {
        currentModel = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in previewLayers {
            layer.path = nil
            layer.isHidden = true
        }
        self.layer?.removeAnimation(forKey: "intentPreviewAppear")
        self.layer?.opacity = 1
        isHidden = true
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        if let currentModel {
            render(currentModel, animation: .none)
        }
    }

    var previewLayers: [CAShapeLayer] {
        [
            surfaceLayer,
            highlightLayer,
            innerStrokeLayer,
            accentStrokeLayer,
            activeStrokeLayer,
            guideLayer,
            activeGuideLayer,
        ]
    }

    func configureLayers(_ backingLayer: CALayer) {
        disableWindowIntentPreviewLayerActions(backingLayer)
        surfaceLayer.fillColor = WindowIntentPreviewPalette.fill
        highlightLayer.fillColor = NSColor.clear.cgColor
        innerStrokeLayer.fillColor = NSColor.clear.cgColor
        innerStrokeLayer.strokeColor = WindowIntentPreviewPalette.innerStroke
        innerStrokeLayer.lineWidth = 0.55
        accentStrokeLayer.fillColor = NSColor.clear.cgColor
        accentStrokeLayer.lineWidth = 0.85
        activeStrokeLayer.fillColor = NSColor.clear.cgColor
        activeStrokeLayer.lineWidth = 1.45
        guideLayer.fillColor = NSColor.clear.cgColor
        guideLayer.lineWidth = 1.5
        guideLayer.lineCap = .round
        activeGuideLayer.fillColor = NSColor.clear.cgColor
        activeGuideLayer.lineWidth = 1.65
        activeGuideLayer.lineCap = .round
        for layer in previewLayers {
            layer.isHidden = true
            disableWindowIntentPreviewLayerActions(layer)
            backingLayer.addSublayer(layer)
        }
    }

    func render(_ model: WindowTabDropPreviewViewModel, animation: WindowIntentPreviewAnimation) {
        let scale = updateContentsScale()
        let zones = localZones(for: model, scale: scale)
        let activeZones = zones.filter(\.isActive)
        let surfacePath = combinedSurfacePath(for: zones, inset: 0)
        let activeSurfacePath = combinedSurfacePath(for: activeZones, inset: 0)
        let insetPath = combinedSurfacePath(for: zones, inset: 1)
        let guidePath = combinedGuidePath(for: zones)
        let activeGuidePath = combinedGuidePath(for: activeZones)
        let appearingStartZones: [WindowIntentPreviewLocalZone]
        let appearingActiveZones: [WindowIntentPreviewLocalZone]
        if animation == .appear {
            appearingStartZones = appearanceStartZones(for: zones)
            appearingActiveZones = appearingStartZones.filter(\.isActive)
        } else {
            appearingStartZones = []
            appearingActiveZones = []
        }
        let appearingSurfacePath = combinedSurfacePath(for: appearingStartZones, inset: 0)
        let appearingActiveSurfacePath = combinedSurfacePath(for: appearingActiveZones, inset: 0)
        let appearingInsetPath = combinedSurfacePath(for: appearingStartZones, inset: 1)
        let appearingGuidePath = combinedGuidePath(for: appearingStartZones)
        let appearingActiveGuidePath = combinedGuidePath(for: appearingActiveZones)
        let style = WindowIntentPreviewLayerStyle(style: model.style, isPointerSettled: model.isPointerSettled)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in previewLayers {
            layer.frame = bounds
            layer.contentsScale = scale
            layer.isHidden = false
        }
        setPath(surfacePath, on: surfaceLayer, animation: animation, key: "surfacePath", appearingStartPath: appearingSurfacePath)
        surfaceLayer.fillColor = WindowIntentPreviewPalette.fill
        setPath(surfacePath, on: highlightLayer, animation: animation, key: "highlightPath", appearingStartPath: appearingSurfacePath)
        highlightLayer.fillColor = WindowIntentPreviewPalette.highlight(alpha: style.highlightAlpha)
        setPath(insetPath, on: innerStrokeLayer, animation: animation, key: "innerStrokePath", appearingStartPath: appearingInsetPath)
        setPath(surfacePath, on: accentStrokeLayer, animation: animation, key: "accentPath", appearingStartPath: appearingSurfacePath)
        accentStrokeLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.inactiveStrokeAlpha)
        setPath(activeSurfacePath, on: activeStrokeLayer, animation: animation, key: "activeStrokePath", appearingStartPath: appearingActiveSurfacePath)
        activeStrokeLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.strokeAlpha)
        setPath(guidePath, on: guideLayer, animation: animation, key: "guidePath", appearingStartPath: appearingGuidePath)
        guideLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.inactiveGuideAlpha)
        setPath(activeGuidePath, on: activeGuideLayer, animation: animation, key: "activeGuidePath", appearingStartPath: appearingActiveGuidePath)
        activeGuideLayer.strokeColor = WindowIntentPreviewPalette.accent(alpha: style.guideAlpha)
        CATransaction.commit()
        if animation == .appear {
            animateInitialOpacity()
        }
    }

    func setPath(
        _ path: CGPath?,
        on layer: CAShapeLayer,
        animation: WindowIntentPreviewAnimation,
        key: String,
        appearingStartPath: CGPath?
    ) {
        let currentPresentationPath = layer.presentation()?.path
        let currentModelPath = layer.path
        layer.removeAnimation(forKey: key)
        layer.path = path
        let fromPath: CGPath?
        let duration: CFTimeInterval
        switch animation {
            case .none:
                return
            case .morph:
                fromPath = currentPresentationPath ?? currentModelPath
                duration = 0.145
            case .appear:
                fromPath = appearingStartPath
                duration = 0.16
        }
        guard let fromPath, let path else { return }

        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = fromPath
        pathAnimation.toValue = path
        pathAnimation.duration = duration
        pathAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        layer.add(pathAnimation, forKey: key)
    }

    func animateInitialOpacity() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "intentPreviewAppear")
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.72
        opacity.toValue = 1
        opacity.duration = 0.13
        opacity.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        layer.opacity = 1
        layer.add(opacity, forKey: "intentPreviewAppear")
    }

    func updateContentsScale() -> CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    func localZones(for model: WindowTabDropPreviewViewModel, scale: CGFloat) -> [WindowIntentPreviewLocalZone] {
        let zones = model.zones.isEmpty
            ? [WindowTabDropPreviewZoneViewModel(frame: model.frame, style: model.style, geometry: model.geometry, isActive: true)]
            : model.zones
        return zones.map { zone in
            WindowIntentPreviewLocalZone(
                frame: alignToBackingPixels(localFrame(for: zone.frame, containerFrame: model.containerFrame), scale: scale),
                style: zone.style,
                geometry: zone.geometry,
                isActive: zone.isActive,
            )
        }
    }

    func localFrame(for screenFrame: CGRect, containerFrame: CGRect) -> CGRect {
        let localMinX = screenFrame.minX - containerFrame.minX
        let localMinY = containerFrame.height - (screenFrame.maxY - containerFrame.minY)
        return CGRect(
            x: localMinX,
            y: localMinY,
            width: screenFrame.width,
            height: screenFrame.height,
        )
    }

    func appearanceStartZones(for zones: [WindowIntentPreviewLocalZone]) -> [WindowIntentPreviewLocalZone] {
        zones.map { zone in
            let startWidth = max(zone.frame.width * 0.88, min(zone.frame.width, 2))
            let startHeight = max(zone.frame.height * 0.88, min(zone.frame.height, 2))
            let startFrame = CGRect(
                x: zone.frame.midX - startWidth / 2,
                y: zone.frame.midY - startHeight / 2,
                width: startWidth,
                height: startHeight,
            )
            return WindowIntentPreviewLocalZone(
                frame: startFrame,
                style: zone.style,
                geometry: zone.geometry,
                isActive: zone.isActive,
            )
        }
    }

    func combinedSurfacePath(for zones: [WindowIntentPreviewLocalZone], inset: CGFloat) -> CGPath? {
        guard !zones.isEmpty else { return nil }
        let path = CGMutablePath()
        for zone in zones {
            let zoneFrame = zone.frame.insetBy(dx: inset, dy: inset)
            guard zoneFrame.width > 0, zoneFrame.height > 0 else { continue }
            let clampedRadius = min(windowTabPreviewCornerRadius, max(0, min(zoneFrame.width, zoneFrame.height) / 2))
            path.addPath(CGPath(
                roundedRect: zoneFrame,
                cornerWidth: max(clampedRadius - inset, 0),
                cornerHeight: max(clampedRadius - inset, 0),
                transform: nil,
            ))
        }
        return path
    }

    func combinedGuidePath(for zones: [WindowIntentPreviewLocalZone]) -> CGPath? {
        let path = CGMutablePath()
        var hasPath = false
        for zone in zones {
            guard let line = windowIntentPreviewGuideLine(for: zone.geometry, in: zone.frame.size) else {
                continue
            }
            path.move(to: CGPoint(x: zone.frame.minX + line.start.x, y: zone.frame.minY + line.start.y))
            path.addLine(to: CGPoint(x: zone.frame.minX + line.end.x, y: zone.frame.minY + line.end.y))
            hasPath = true
        }
        guard hasPath else { return nil }
        return path
    }

    func alignToBackingPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let alignedMinX = (rect.minX * scale).rounded() / scale
        let alignedMinY = (rect.minY * scale).rounded() / scale
        let alignedMaxX = (rect.maxX * scale).rounded() / scale
        let alignedMaxY = (rect.maxY * scale).rounded() / scale
        return CGRect(
            x: alignedMinX,
            y: alignedMinY,
            width: max(alignedMaxX - alignedMinX, 0),
            height: max(alignedMaxY - alignedMinY, 0),
        )
    }
}

struct WindowIntentPreviewLocalZone {
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let isActive: Bool
}

enum WindowIntentPreviewAnimation {
    case none
    case appear
    case morph
}

struct WindowIntentPreviewContentKey: Equatable {
    let containerSize: CGSize
    let referenceWindowId: UInt32?
    let frame: CGRect
    let style: WindowTabDropPreviewStyle
    let geometry: WindowTabDropPreviewGeometry
    let zones: [WindowTabDropPreviewZoneViewModel]

    init(model: WindowTabDropPreviewViewModel) {
        containerSize = model.containerFrame.size
        referenceWindowId = model.referenceWindowId
        frame = model.frame
        style = model.style
        geometry = model.geometry
        zones = model.zones
    }

    func canMorph(to next: WindowIntentPreviewContentKey) -> Bool {
        referenceWindowId == next.referenceWindowId
            && containerSize.isNearlyEqual(to: next.containerSize, tolerance: 1)
    }
}

extension CGSize {
    func isNearlyEqual(to other: CGSize, tolerance: CGFloat) -> Bool {
        abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

struct WindowIntentPreviewLayerStyle {
    let highlightAlpha: CGFloat
    let inactiveStrokeAlpha: CGFloat
    let strokeAlpha: CGFloat
    let inactiveGuideAlpha: CGFloat
    let guideAlpha: CGFloat

    init(style: WindowTabDropPreviewStyle, isPointerSettled _: Bool) {
        let boost: CGFloat = 1
        switch style {
            case .tabInsert:
                highlightAlpha = 0.07 * boost
                inactiveStrokeAlpha = 0.16
                strokeAlpha = 0.36 * boost
                inactiveGuideAlpha = 0.12
                guideAlpha = 0.34 * boost
            case .detach:
                highlightAlpha = 0.06 * boost
                inactiveStrokeAlpha = 0.14
                strokeAlpha = 0.32 * boost
                inactiveGuideAlpha = 0.10
                guideAlpha = 0.28 * boost
            case .stackSplit:
                highlightAlpha = 0.065 * boost
                inactiveStrokeAlpha = 0.17
                strokeAlpha = 0.38 * boost
                inactiveGuideAlpha = 0.12
                guideAlpha = 0.36 * boost
            case .swap:
                highlightAlpha = 0.05 * boost
                inactiveStrokeAlpha = 0.15
                strokeAlpha = 0.34 * boost
                inactiveGuideAlpha = 0
                guideAlpha = 0
            case .workspaceMove, .sidebarWorkspaceMove:
                highlightAlpha = 0.06 * boost
                inactiveStrokeAlpha = 0.14
                strokeAlpha = 0.32 * boost
                inactiveGuideAlpha = 0.10
                guideAlpha = 0.28 * boost
        }
    }
}

enum WindowIntentPreviewPalette {
    static let fillColor = mattePanelNSColor
    static let fill = fillColor.cgColor
    static let innerStroke = NSColor.white.withAlphaComponent(0.025).cgColor
    static let accentColor = fillColor

    static func highlight(alpha: CGFloat) -> CGColor {
        NSColor.white.withAlphaComponent(min(max(alpha * 0.24, 0), 0.035)).cgColor
    }

    static func accent(alpha: CGFloat) -> CGColor {
        accentColor.cgColor
    }
}

final class WindowIntentPreviewDisabledLayerAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

func disableWindowIntentPreviewLayerActions(_ layer: CALayer) {
    let action = WindowIntentPreviewDisabledLayerAction()
    layer.actions = [
        "backgroundColor": action,
        "bounds": action,
        "contents": action,
        "frame": action,
        "hidden": action,
        "opacity": action,
        "path": action,
        "position": action,
        "strokeColor": action,
        "fillColor": action,
        "sublayers": action,
    ]
}
