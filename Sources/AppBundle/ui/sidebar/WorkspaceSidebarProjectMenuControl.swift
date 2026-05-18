import AppKit

final class WorkspaceSidebarProjectMenuControl: NSControl {
    let pillLayer = CALayer()
    let titleField = NSTextField(labelWithString: "")
    let chevronView = NSImageView()
    var isExternallyHovered = false
    var isPressed = false
    var preferredSize = NSSize(width: 92, height: workspaceSidebarPagerHeight)

    override var intrinsicContentSize: NSSize { preferredSize }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        pillLayer.masksToBounds = true
        layer?.addSublayer(pillLayer)
        configureTitleField()
        configureChevron()
        toolTip = "Projects"
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Projects")
        update(title: "Project", width: preferredSize.width, isHovered: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateColors()
        sendAction(action, to: target)
        isPressed = false
        updateColors()
    }
}
