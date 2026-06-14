import AppKit

func workspaceSidebarSwatchImage(draw: () -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    image.lockFocus()
    draw()
    image.unlockFocus()
    image.isTemplate = false
    return image
}

func drawWorkspaceSidebarSwatchCircle(fill: NSColor, stroke: NSColor, lineWidth: CGFloat) {
    let circlePath = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 10, height: 10))
    fill.setFill()
    circlePath.fill()
    stroke.setStroke()
    circlePath.lineWidth = lineWidth
    circlePath.stroke()
}
