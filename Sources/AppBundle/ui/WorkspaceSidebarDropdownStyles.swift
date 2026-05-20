import SwiftUI

struct WorkspaceSidebarDropdownControlStyle: ViewModifier {
    let isActive: Bool
    var activeFill: Color = Color.white.opacity(0.12)
    var activeStroke: Color = Color.white.opacity(0.18)
    var inactiveFill: Color = Color.white.opacity(0.06)
    var inactiveHoverFill: Color = Color.white.opacity(0.10)
    var inactiveStroke: Color = Color.white.opacity(0.08)
    var inactiveHoverStroke: Color = Color.white.opacity(0.14)
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                    .fill(controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                            .strokeBorder(controlStroke, lineWidth: isHovered || isActive ? 0.65 : 0.5)
                    }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var controlFill: Color {
        if isActive {
            return activeFill
        }
        return isHovered ? inactiveHoverFill : inactiveFill
    }

    private var controlStroke: Color {
        if isActive {
            return activeStroke
        }
        return isHovered ? inactiveHoverStroke : inactiveStroke
    }
}

struct WorkspaceSidebarDropdownMenuRowStyle: ViewModifier {
    let isSelected: Bool
    var rowHeight: CGFloat = workspaceSidebarDropdownHeight
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    private var rowFill: Color {
        if isSelected {
            return Color.white.opacity(isHovered ? 0.10 : 0.06)
        }
        return Color.white.opacity(isHovered ? 0.07 : 0)
    }
}

func checkmark(isVisible: Bool) -> some View {
    Image(systemName: "checkmark")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Color.white.opacity(isVisible ? 0.80 : 0))
}
