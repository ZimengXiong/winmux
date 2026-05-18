import SwiftUI

struct WorkspaceSidebarStatusInlineItems: View {
    let systemStatus: WorkspaceSidebarSystemStatusSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            WorkspaceSidebarStatusInlineItem(
                symbolName: systemStatus.battery.symbolName,
                label: systemStatus.battery.label,
                tint: systemStatus.battery.tintColor,
                accessibilityDescription: systemStatus.battery.accessibilityDescription,
            )
            WorkspaceSidebarStatusInlineItem(
                symbolName: systemStatus.audio.symbolName,
                label: systemStatus.audio.label,
                tint: systemStatus.audio.tintColor,
                accessibilityDescription: systemStatus.audio.accessibilityDescription,
            )
            WorkspaceSidebarStatusInlineItem(
                symbolName: systemStatus.network.symbolName,
                label: systemStatus.network.label,
                tint: systemStatus.network.tintColor,
                accessibilityDescription: systemStatus.network.accessibilityDescription,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceSidebarStatusInlineItem: View {
    let symbolName: String
    let label: String
    let tint: Color
    let accessibilityDescription: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint.opacity(0.82))
                .frame(width: 12, alignment: .center)

            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}
