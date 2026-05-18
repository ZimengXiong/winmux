import Foundation
import SwiftUI

struct WorkspaceSidebarStatusClockBlock: View {
    let date: Date
    let showsDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.hour().minute().second())
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .allowsTightening(true)
            if showsDate {
                Text(date, format: .dateTime.month(.wide).day())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
