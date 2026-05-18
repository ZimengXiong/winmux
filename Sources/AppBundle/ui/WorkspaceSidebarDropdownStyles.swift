import SwiftUI

struct WorkspaceSidebarDropdownControlStyle: ViewModifier {
    let isActive: Bool
    var activeFill: Color = Color.white.opacity(0.09)
    var activeStroke: Color = Color.white.opacity(0.12)

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: workspaceSidebarDropdownHeight)
            .background {
                RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                    .fill(isActive ? activeFill : Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                            .strokeBorder(isActive ? activeStroke : Color.white.opacity(0.07), lineWidth: 0.5)
                    }
            }
            .contentShape(Rectangle())
    }
}

struct WorkspaceSidebarDropdownMenuRowStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .frame(height: workspaceSidebarMenuRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.055) : Color.clear)
            }
    }
}

func checkmark(isVisible: Bool) -> some View {
    Image(systemName: "checkmark")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Color.white.opacity(isVisible ? 0.80 : 0))
}
