import Foundation
import SwiftUI

struct WorkspaceSidebarExpandedStatusCard: View {
    let date: Date
    let systemStatus: WorkspaceSidebarSystemStatusSnapshot
    let sectionWidth: CGFloat

    @MainActor private var showsDate: Bool { config.workspaceSidebar.showDate }
    @MainActor private var showsStatusPills: Bool { config.workspaceSidebar.showStatusPills }

    private var accessibilitySummary: String {
        var parts = [date.formatted(date: .omitted, time: .standard)]
        if showsDate {
            parts.append(date.formatted(date: .complete, time: .omitted))
        }
        if showsStatusPills {
            parts.append(systemStatus.battery.accessibilityDescription)
            parts.append(systemStatus.audio.accessibilityDescription)
            parts.append(systemStatus.network.accessibilityDescription)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WorkspaceSidebarStatusClockBlock(date: date, showsDate: showsDate)
            if showsStatusPills {
                WorkspaceSidebarStatusInlineItems(systemStatus: systemStatus)
            }
        }
        .padding(.leading, workspaceSidebarExpandedStatusLeadingPadding)
        .padding(.trailing, workspaceSidebarExpandedStatusTrailingPadding)
        .padding(.vertical, 10)
        .frame(width: sectionWidth, alignment: .leading)
        .background(WorkspaceSidebarStatusCardBackground())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }
}
