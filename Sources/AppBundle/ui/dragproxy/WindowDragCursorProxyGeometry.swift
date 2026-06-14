import AppKit

func windowDragCursorProxyFrame(mouseScreenPoint: CGPoint, proxySize: CGSize) -> CGRect {
    let screenFrame = NSScreen.screens
        .first(where: { $0.frame.contains(mouseScreenPoint) })?
        .visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

    var x = mouseScreenPoint.x - (proxySize.width / 2)
    var y = mouseScreenPoint.y - (proxySize.height / 2)
    if x + proxySize.width > screenFrame.maxX {
        x = screenFrame.maxX - proxySize.width
    } else if x < screenFrame.minX {
        x = screenFrame.minX
    }
    if y < screenFrame.minY {
        y = screenFrame.minY
    } else if y + proxySize.height > screenFrame.maxY {
        y = screenFrame.maxY - proxySize.height
    }
    return CGRect(x: x, y: y, width: proxySize.width, height: proxySize.height)
}
