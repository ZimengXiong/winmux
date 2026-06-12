import SwiftUI

struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 6) {
            appIcon(size: 14)

            Text(tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(tabForegroundStyle)
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .fill(Color.white.opacity(tab.isActive ? GlassToken.fillActive : GlassToken.fillFaint))
        }
        .overlay {
            RoundedRectangle(cornerRadius: windowTabStripInnerCornerRadius, style: .continuous)
                .stroke(tabStrokeStyle, lineWidth: StrokeToken.control)
        }
        .opacity(isDragSource ? 0.55 : 1.0)
        .contentShape(Rectangle())
    }

    private var tabForegroundStyle: Color {
        if tab.isActive { return Color.white.opacity(GlassToken.textPrimary) }
        if isDragSource { return Color.white.opacity(GlassToken.textSecondary) }
        return Color.white.opacity(isHovered ? GlassToken.textSecondary : GlassToken.textTertiary)
    }

    private var tabStrokeStyle: Color {
        if tab.isActive { return Color.white.opacity(GlassToken.strokeActive) }
        return Color.white.opacity(isHovered ? GlassToken.strokeHover : GlassToken.strokeResting)
    }
}
