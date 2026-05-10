import AppKit
import Common

struct WindowResizePreviewLocalItem: Identifiable, Equatable {
    let id: UInt32
    let frame: CGRect
    let appName: String
    let icons: [WindowResizePreviewIcon]
    let isTabGroup: Bool
    let drawsFrameOnly: Bool
    let frameOnlyHeaderHeight: CGFloat
}

@MainActor
final class WindowResizePreviewCompositorView: NSView {
    private var itemLayers: [UInt32: WindowResizePreviewItemLayer] = [:]
    private var iconCache: [WindowResizePreviewIcon: CGImage] = [:]

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

    func update(_ items: [WindowResizePreviewLocalItem]) {
        let visibleIds = Set(items.map(\.id))
        var appearingLayers: [WindowResizePreviewItemLayer] = []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for staleId in itemLayers.keys where !visibleIds.contains(staleId) {
            itemLayers[staleId]?.removeFromSuperlayer()
            itemLayers.removeValue(forKey: staleId)
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for item in items {
            let isNewLayer = itemLayers[item.id] == nil
            let itemLayer = itemLayers[item.id] ?? WindowResizePreviewItemLayer()
            if isNewLayer {
                itemLayer.opacity = 0
                itemLayers[item.id] = itemLayer
                layer?.addSublayer(itemLayer)
                appearingLayers.append(itemLayer)
            }
            itemLayer.update(item, scale: scale, iconResolver: resolvedIconImage)
        }
        CATransaction.commit()
        appearingLayers.forEach { $0.animateAppear() }
        isHidden = items.isEmpty
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for itemLayer in itemLayers.values {
            itemLayer.removeFromSuperlayer()
        }
        itemLayers.removeAll()
        isHidden = true
        CATransaction.commit()
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

