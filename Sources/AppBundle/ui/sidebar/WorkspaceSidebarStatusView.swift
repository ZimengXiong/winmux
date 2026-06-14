import AppKit
import Foundation
import SwiftUI

struct WorkspaceSidebarStatusView: View {
    let sectionWidth: CGFloat
    let isCompact: Bool
    let showsDate: Bool

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
                        sectionWidth: sectionWidth,
                        showsDate: showsDate,
                    )
                }
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.16), value: isCompact)
    }
}
