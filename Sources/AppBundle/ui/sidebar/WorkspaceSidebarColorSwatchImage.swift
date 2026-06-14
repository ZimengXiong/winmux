import AppKit

func workspaceSidebarProjectColorSwatchImage(hex: String, isSelected: Bool) -> NSImage {
    let color = workspaceSidebarNSColor(hex: hex) ?? NSColor.white.withAlphaComponent(0.65)
    return workspaceSidebarSwatchImage {
        drawWorkspaceSidebarSwatchCircle(
            fill: color,
            stroke: NSColor.white.withAlphaComponent(isSelected ? 0.92 : 0.26),
            lineWidth: isSelected ? 1.5 : 1,
        )
        guard isSelected else { return }
        drawWorkspaceSidebarSwatchCheckmark()
    }
}

func drawWorkspaceSidebarSwatchCheckmark() {
    let checkPath = NSBezierPath()
    checkPath.move(to: NSPoint(x: 5.2, y: 8.0))
    checkPath.line(to: NSPoint(x: 7.2, y: 6.0))
    checkPath.line(to: NSPoint(x: 10.9, y: 10.2))
    checkPath.lineCapStyle = .round
    checkPath.lineJoinStyle = .round
    checkPath.lineWidth = 1.5
    NSColor.white.setStroke()
    checkPath.stroke()
}
