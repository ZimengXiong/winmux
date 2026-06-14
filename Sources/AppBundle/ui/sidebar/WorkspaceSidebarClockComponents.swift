import Foundation

struct WorkspaceSidebarClockComponents {
    let hour: String
    let minute: String
    let second: String

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        hour = Self.format(components.hour)
        minute = Self.format(components.minute)
        second = Self.format(components.second)
    }

    private static func format(_ value: Int?) -> String {
        String(format: "%02d", value ?? 0)
    }
}
