import AppKit
import Foundation
import SwiftUI

struct WorkspaceSidebarStatusView: View {
    let sectionWidth: CGFloat
    let isCompact: Bool
    let showsSeconds: Bool
    let showsDate: Bool
    let showsWeekday: Bool

    var body: some View {
        Group {
            if isCompact {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WorkspaceSidebarCompactClockCard(
                        date: context.date,
                        sectionWidth: sectionWidth,
                        showsSeconds: showsSeconds,
                    )
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WorkspaceSidebarExpandedStatusCard(
                        date: context.date,
                        sectionWidth: sectionWidth,
                        showsSeconds: showsSeconds,
                        showsDate: showsDate,
                        showsWeekday: showsWeekday,
                    )
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.16), value: isCompact)
    }
}
