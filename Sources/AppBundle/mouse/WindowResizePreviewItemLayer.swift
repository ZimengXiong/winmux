import AppKit
import Common

final class WindowResizePreviewItemLayer: CALayer {
    private let surfaceLayer = CAShapeLayer()
    private let topBarLayer = CAShapeLayer()
    private let mockTabStrokeLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private var iconLayers: [CALayer] = []

    override init() {
        super.init()
        masksToBounds = false
        disableResizePreviewLayerActions(self)

        surfaceLayer.fillColor = ResizePreviewPalette.fill
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.strokeColor = ResizePreviewPalette.stroke
        strokeLayer.lineWidth = 0.7
        topBarLayer.fillColor = ResizePreviewPalette.tabGroupBar
        mockTabStrokeLayer.fillColor = NSColor.clear.cgColor
        mockTabStrokeLayer.strokeColor = ResizePreviewPalette.sourceMockTabStroke
        mockTabStrokeLayer.lineWidth = 0.7
        [surfaceLayer, topBarLayer, mockTabStrokeLayer, strokeLayer].forEach {
            disableResizePreviewLayerActions($0)
            addSublayer($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    func animateAppear() {
        removeAnimation(forKey: "resizePreviewAppear")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        opacity = 1
        add(fade, forKey: "resizePreviewAppear")
    }

    func update(
        _ item: WindowResizePreviewLocalItem,
        scale: CGFloat,
        iconResolver: (WindowResizePreviewIcon) -> CGImage?,
    ) {
        contentsScale = scale
        frame = item.frame
        let localBounds = CGRect(origin: .zero, size: item.frame.size)
        if item.isTabGroup, item.drawsFrameOnly {
            updateFrameOnlyShell(item: item, bounds: localBounds, scale: scale)
            return
        }
        let radius = windowResizePreviewCornerRadius(for: localBounds)
        let path = CGPath(roundedRect: localBounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        surfaceLayer.fillRule = .nonZero
        surfaceLayer.fillColor = ResizePreviewPalette.fill
        surfaceLayer.frame = localBounds
        surfaceLayer.path = path
        surfaceLayer.contentsScale = scale
        mockTabStrokeLayer.isHidden = true
        mockTabStrokeLayer.path = nil
        strokeLayer.strokeColor = ResizePreviewPalette.stroke
        strokeLayer.lineWidth = 0.7
        strokeLayer.frame = localBounds
        strokeLayer.path = path
        strokeLayer.contentsScale = scale
        updateTopBar(item: item, radius: radius, scale: scale)
        updateIcons(item: item, scale: scale, iconResolver: iconResolver)
    }

    private func updateFrameOnlyShell(item: WindowResizePreviewLocalItem, bounds localBounds: CGRect, scale: CGFloat) {
        hideIconLayers()

        let shellPath = windowResizePreviewTabGroupShellPath(
            in: localBounds,
            headerHeight: item.frameOnlyHeaderHeight,
        )
        let mockTabsPath = windowResizePreviewMockTabPillsPath(
            in: localBounds,
            headerHeight: item.frameOnlyHeaderHeight,
            tabCount: item.icons.count,
        )
        surfaceLayer.fillRule = .evenOdd
        surfaceLayer.fillColor = ResizePreviewPalette.sourceFrameFill
        surfaceLayer.frame = localBounds
        surfaceLayer.path = shellPath
        surfaceLayer.contentsScale = scale

        topBarLayer.isHidden = false
        topBarLayer.fillColor = ResizePreviewPalette.sourceMockTabFill
        topBarLayer.frame = localBounds
        topBarLayer.path = mockTabsPath
        topBarLayer.contentsScale = scale

        mockTabStrokeLayer.isHidden = false
        mockTabStrokeLayer.strokeColor = ResizePreviewPalette.sourceMockTabStroke
        mockTabStrokeLayer.lineWidth = 0.7
        mockTabStrokeLayer.frame = localBounds
        mockTabStrokeLayer.path = mockTabsPath
        mockTabStrokeLayer.contentsScale = scale

        strokeLayer.strokeColor = ResizePreviewPalette.sourceFrameStroke
        strokeLayer.lineWidth = 0.8
        strokeLayer.frame = localBounds
        strokeLayer.path = shellPath
        strokeLayer.contentsScale = scale
    }

    private func updateTopBar(item: WindowResizePreviewLocalItem, radius: CGFloat, scale: CGFloat) {
        topBarLayer.isHidden = !item.isTabGroup
        guard item.isTabGroup else {
            topBarLayer.path = nil
            return
        }
        let localBounds = CGRect(origin: .zero, size: item.frame.size)
        let height = min(max(item.frame.height * 0.12, 16), 30)
        let insetBounds = localBounds.insetBy(dx: 4, dy: 4)
        let barRect = CGRect(x: insetBounds.minX, y: insetBounds.minY, width: insetBounds.width, height: height)
        topBarLayer.fillColor = ResizePreviewPalette.tabGroupBar
        topBarLayer.frame = localBounds
        topBarLayer.path = CGPath(
            roundedRect: barRect,
            cornerWidth: max(radius * 0.7, 4),
            cornerHeight: max(radius * 0.7, 4),
            transform: nil,
        )
        topBarLayer.contentsScale = scale
    }

    private func updateIcons(
        item: WindowResizePreviewLocalItem,
        scale: CGFloat,
        iconResolver: (WindowResizePreviewIcon) -> CGImage?,
    ) {
        let visibleIcons = item.isTabGroup ? item.icons : Array(item.icons.prefix(1))
        let iconCount = max(visibleIcons.count, 1)
        while iconLayers.count < iconCount {
            let iconLayer = CALayer()
            iconLayer.masksToBounds = true
            iconLayer.contentsGravity = .resizeAspect
            disableResizePreviewLayerActions(iconLayer)
            addSublayer(iconLayer)
            iconLayers.append(iconLayer)
        }
        for extraIndex in iconCount..<iconLayers.count {
            iconLayers[extraIndex].isHidden = true
        }

        let iconSize = min(max(min(item.frame.width, item.frame.height) * 0.18, 32), 72)
        for index in 0..<iconCount {
            let iconLayer = iconLayers[index]
            iconLayer.isHidden = false
            iconLayer.contentsScale = scale
            iconLayer.cornerRadius = max(iconSize * 0.18, 6)
            iconLayer.backgroundColor = ResizePreviewPalette.fallbackIconFill
            let icon = visibleIcons.getOrNil(atIndex: index)
            iconLayer.contents = icon.flatMap(iconResolver)
            if iconLayer.contents == nil {
                iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
                let textLayer = fallbackTextLayer(text: fallbackLetter(icon: icon, item: item), size: iconSize, scale: scale)
                iconLayer.addSublayer(textLayer)
            } else {
                iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            }

            let offset = item.isTabGroup && iconCount > 1
                ? windowResizePreviewStackOffset(index, iconCount: iconCount, size: iconSize)
                : .zero
            let center = CGPoint(
                x: item.frame.width / 2 + offset.width,
                y: item.frame.height / 2 + offset.height,
            )
            iconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            iconLayer.position = center
            iconLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(windowResizePreviewStackRotation(index) * Double.pi / 180)))
            iconLayer.zPosition = CGFloat(iconCount - index)
        }
    }

    private func hideIconLayers() {
        for iconLayer in iconLayers {
            iconLayer.isHidden = true
            iconLayer.contents = nil
            iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
    }

    private func fallbackTextLayer(text: String, size: CGFloat, scale: CGFloat) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.frame = CGRect(x: 0, y: (size - size * 0.52) / 2 - 1, width: size, height: size * 0.58)
        textLayer.string = text
        textLayer.alignmentMode = .center
        textLayer.contentsScale = scale
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.82).cgColor
        textLayer.font = NSFont.systemFont(ofSize: size * 0.42, weight: .bold)
        textLayer.fontSize = size * 0.42
        disableResizePreviewLayerActions(textLayer)
        return textLayer
    }

    private func fallbackLetter(icon: WindowResizePreviewIcon?, item: WindowResizePreviewLocalItem) -> String {
        (icon?.appName ?? item.appName).first.map { String($0).uppercased() } ?? "W"
    }
}

