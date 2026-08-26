import AppKit
import Common
import SwiftUI

enum WindowResizePreviewPresentation {
    case detailed
    case resizeOverlay
}

@MainActor
final class WindowResizePreviewCompositorView: NSView {
    private var itemLayers: [UInt32: WindowResizePreviewItemLayer] = [:]
    private var iconCache: [WindowResizePreviewIcon: CGImage] = [:]
    private var materialViews: [UInt32: NSVisualEffectView] = [:]
    private var tintLayers: [UInt32: CALayer] = [:]

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let backingLayer = CALayer()
        backingLayer.masksToBounds = false
        backingLayer.isGeometryFlipped = true
        layer = backingLayer
        disableResizePreviewLayerActions(backingLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ items: [WindowResizePreviewItem], presentation: WindowResizePreviewPresentation) {
        let visibleIds = Set(items.map(\.id))
        var appearingLayers: [WindowResizePreviewItemLayer] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for staleId in itemLayers.keys where !visibleIds.contains(staleId) {
            itemLayers[staleId]?.removeFromSuperlayer()
            itemLayers.removeValue(forKey: staleId)
        }
        for staleId in materialViews.keys where !visibleIds.contains(staleId) || presentation != .resizeOverlay {
            materialViews[staleId]?.removeFromSuperview()
            materialViews.removeValue(forKey: staleId)
            tintLayers.removeValue(forKey: staleId)
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for item in items {
            if presentation == .resizeOverlay {
                updateMaterialView(for: item)
            }
            let isNewLayer = itemLayers[item.id] == nil
            let itemLayer = itemLayers[item.id] ?? WindowResizePreviewItemLayer()
            if isNewLayer {
                itemLayer.opacity = 0
                itemLayer.zPosition = 1
                itemLayers[item.id] = itemLayer
                layer?.addSublayer(itemLayer)
                appearingLayers.append(itemLayer)
            }
            itemLayer.update(item, scale: scale, presentation: presentation, iconResolver: resolvedIconImage)
        }
        CATransaction.commit()
        if presentation == .detailed {
            appearingLayers.forEach { $0.animateAppear() }
        } else {
            appearingLayers.forEach { $0.opacity = 1 }
        }
        isHidden = items.isEmpty
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for itemLayer in itemLayers.values {
            itemLayer.removeFromSuperlayer()
        }
        itemLayers.removeAll()
        for materialView in materialViews.values {
            materialView.removeFromSuperview()
        }
        materialViews.removeAll()
        tintLayers.removeAll()
        isHidden = true
        CATransaction.commit()
    }

    private func updateMaterialView(for item: WindowResizePreviewItem) {
        let materialView = materialViews[item.id] ?? makeMaterialView(for: item.id)
        materialView.frame = item.frame
        let radius = windowResizePreviewCornerRadius(for: item.frame)
        materialView.layer?.cornerRadius = radius
        materialView.layer?.masksToBounds = true

        let tintLayer = tintLayers[item.id] ?? makeTintLayer(for: item.id, in: materialView)
        let usesSolidTint = config.workspaceSidebar.chromeStyle == .solid
        tintLayer.frame = materialView.bounds
        tintLayer.backgroundColor = NSColor(config.workspaceSidebar.resolvedSolidChromeColor)
            .withAlphaComponent(0.42)
            .cgColor
        tintLayer.isHidden = !usesSolidTint
    }

    private func makeMaterialView(for id: UInt32) -> NSVisualEffectView {
        let materialView = NSVisualEffectView()
        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.zPosition = 0
        addSubview(materialView)
        materialViews[id] = materialView
        return materialView
    }

    private func makeTintLayer(for id: UInt32, in materialView: NSVisualEffectView) -> CALayer {
        let tintLayer = CALayer()
        tintLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        disableResizePreviewLayerActions(tintLayer)
        materialView.layer?.addSublayer(tintLayer)
        tintLayers[id] = tintLayer
        return tintLayer
    }

    private func resolvedIconImage(_ icon: WindowResizePreviewIcon) -> CGImage? {
        if let cached = iconCache[icon] {
            return cached
        }
        guard let image = appIconImage(bundleIdentifier: icon.appBundleId, bundlePath: icon.appBundlePath) else {
            return nil
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        iconCache[icon] = cgImage
        return cgImage
    }
}
