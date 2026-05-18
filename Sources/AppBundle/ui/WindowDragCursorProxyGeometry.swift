import AppKit

func windowDragCursorProxyFrame(mouseScreenPoint: CGPoint, proxySize: CGSize) -> CGRect {
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
    return CGRect(x: x, y: y, width: proxySize.width, height: proxySize.height)
}
