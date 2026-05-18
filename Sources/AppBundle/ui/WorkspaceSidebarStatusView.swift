import AppKit
import Foundation
import SwiftUI

struct WorkspaceSidebarStatusView: View {
    let sectionWidth: CGFloat
    let isCompact: Bool

    @State private var systemStatus = WorkspaceSidebarSystemStatusSnapshot.current()

    var body: some View {
        Group {
            if isCompact {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WorkspaceSidebarCompactClockCard(
                        date: context.date,
                        sectionWidth: sectionWidth,
                    )
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WorkspaceSidebarExpandedStatusCard(
                        date: context.date,
                        systemStatus: systemStatus,
                        sectionWidth: sectionWidth,
                    )
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await refreshSystemStatus()
        }
        .animation(.easeInOut(duration: 0.16), value: isCompact)
    }

    private func refreshSystemStatus() async {
        systemStatus = .current()
        while !Task.isCancelled {
            try? await Task.sleep(for: workspaceSidebarStatusRefreshInterval)
            guard !Task.isCancelled else { return }
            systemStatus = .current()
        }
    }
}
