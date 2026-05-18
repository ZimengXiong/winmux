import AppKit

extension WorkspaceSidebarProjectMenuControl {
    func update(title: String, width: CGFloat, isHovered: Bool) {
        let resolvedWidth = max(width, 1)
        let resolvedHeight = max(bounds.height, workspaceSidebarPagerHeight)
        let nextSize = NSSize(width: resolvedWidth, height: resolvedHeight)
        if preferredSize != nextSize {
            preferredSize = nextSize
            invalidateIntrinsicContentSize()
        }
        titleField.stringValue = title
        isExternallyHovered = isHovered
        updateColors()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pillHeight = min(bounds.height, 26)
        let pillFrame = CGRect(x: 0, y: (bounds.height - pillHeight) / 2, width: bounds.width, height: pillHeight)
        pillLayer.frame = pillFrame
        pillLayer.cornerRadius = pillHeight / 2

        let horizontalInset: CGFloat = 10
        let chevronSize: CGFloat = 11
        let chevronGap: CGFloat = 6
        let titleMaxWidth = max(bounds.width - horizontalInset * 2 - chevronSize - chevronGap, 12)
        let titleWidth = min(ceil(titleField.intrinsicContentSize.width) + 6, titleMaxWidth)
        let titleHeight: CGFloat = 16
        titleField.frame = NSRect(
            x: pillFrame.minX + horizontalInset,
            y: pillFrame.midY - titleHeight / 2 - 0.5,
            width: titleWidth,
            height: titleHeight,
        )
        chevronView.frame = NSRect(
            x: pillFrame.maxX - horizontalInset - chevronSize,
            y: pillFrame.midY - chevronSize / 2 - 0.5,
            width: chevronSize,
            height: chevronSize,
        )
    }
}
