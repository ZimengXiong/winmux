import AppKit

final class ResizePreviewDisabledLayerAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

func disableResizePreviewLayerActions(_ layer: CALayer) {
    let action = ResizePreviewDisabledLayerAction()
    layer.actions = [
        "backgroundColor": action,
        "bounds": action,
        "contents": action,
        "cornerRadius": action,
        "frame": action,
        "hidden": action,
        "opacity": action,
        "path": action,
        "position": action,
        "sublayers": action,
        "transform": action,
    ]
}
