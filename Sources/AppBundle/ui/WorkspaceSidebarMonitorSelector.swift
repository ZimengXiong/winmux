import AppKit
import Common
import SwiftUI

// MARK: - Monitor Selector

struct WorkspaceSidebarMonitorSelector: View {
    let scopes: [WorkspaceSidebarMonitorScopeViewModel]
    let selectedScopeId: String
    let expansionProgress: CGFloat

    @State private var hoveredScopeId: String? = nil

    private var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(scopes) { scope in
                    Button {
                        selectWorkspaceSidebarMonitorScope(scope.id)
                    } label: {
                        scopeLabel(scope)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(scopeAccessibilityLabel(scope))
                    .onHover { hover in
                        hoveredScopeId = hover ? scope.id : (hoveredScopeId == scope.id ? nil : hoveredScopeId)
                    }
                    .background {
                        if workspaceSidebarMonitorScopePoint(scope.id) != nil {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: WorkspaceSidebarDropTargetPreferenceKey.self,
                                    value: [WorkspaceSidebarDropTargetFrame(
                                        kind: .monitor(scope.id),
                                        frame: geometry.frame(in: .named("workspaceSidebarContent")),
                                    )],
                                )
                            }
                        }
                    }
                }
            }
            .frame(minWidth: sectionWidth, alignment: .leading)
        }
        .frame(width: sectionWidth, height: 30, alignment: .leading)
        .clipped()
    }

    private func scopeLabel(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> some View {
        let isSelected = selectedScopeId == scope.id
        let isHovered = hoveredScopeId == scope.id
        return HStack(spacing: 5) {
            Image(systemName: scope.systemImageName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12, height: 12)
            Text(scope.displayName)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
            if scope.isFocusedMonitor && scope.id != workspaceSidebarFocusedScopeId {
                Circle()
                    .fill(Color.accentColor.opacity(isSelected ? 0.95 : 0.72))
                    .frame(width: 4, height: 4)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.72))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            Capsule(style: .continuous)
                .fill(scopeFill(isSelected: isSelected, isHovered: isHovered))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(scopeBorder(isSelected: isSelected, isHovered: isHovered), lineWidth: 0.5)
                }
        )
        .contentShape(Capsule(style: .continuous))
    }

    private func scopeFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isHovered {
            return Color.white.opacity(0.07)
        }
        return Color.white.opacity(0.035)
    }

    private func scopeBorder(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.36)
        }
        return Color.white.opacity(isHovered ? 0.10 : 0.06)
    }

    private func scopeAccessibilityLabel(_ scope: WorkspaceSidebarMonitorScopeViewModel) -> String {
        if let subtitle = scope.subtitle {
            return "\(scope.displayName), \(subtitle)"
        }
        return scope.displayName
    }
}

