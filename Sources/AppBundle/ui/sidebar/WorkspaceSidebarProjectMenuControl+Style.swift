import AppKit

extension WorkspaceSidebarProjectMenuControl {
    func configureTitleField() {
        titleField.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.backgroundColor = .clear
        titleField.isBordered = false
        titleField.isEditable = false
        titleField.isSelectable = false
        addSubview(titleField)
    }

    func configureChevron() {
        chevronView.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevronView.symbolConfiguration = .init(pointSize: 8.5, weight: .semibold)
        chevronView.imageScaling = .scaleProportionallyDown
        addSubview(chevronView)
    }

    func updateColors() {
        let textAlpha: CGFloat = isPressed ? 0.90 : isExternallyHovered ? 0.82 : 0.72
        titleField.textColor = NSColor.white.withAlphaComponent(textAlpha)
        chevronView.contentTintColor = NSColor.white.withAlphaComponent(textAlpha)
        pillLayer.backgroundColor = NSColor.white.withAlphaComponent(isPressed ? 0.095 : 0.065).cgColor
        pillLayer.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        pillLayer.borderWidth = 0.5
    }
}
