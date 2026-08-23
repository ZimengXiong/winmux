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

struct WorkspaceSidebarExpandedClockDateLines: Equatable {
    let weekday: String
    let monthAndDay: String

    init(
        date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        weekday = Self.format(date, template: "EEEE", locale: locale, calendar: calendar)
        monthAndDay = Self.format(date, template: "MMMMd", locale: locale, calendar: calendar)
    }

    private static func format(_ date: Date, template: String, locale: Locale, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

func workspaceSidebarExpandedClockDateLineCount(showsDate: Bool, showsWeekday: Bool) -> Int {
    (showsDate ? 1 : 0) + (showsWeekday ? 1 : 0)
}

func workspaceSidebarExpandedClockCardHeight(showsDate: Bool, showsWeekday: Bool) -> CGFloat {
    68 + CGFloat(workspaceSidebarExpandedClockDateLineCount(
        showsDate: showsDate,
        showsWeekday: showsWeekday
    )) * 19
}

func workspaceSidebarExpandedClockAccessibilitySummary(
    date: Date,
    showsSeconds: Bool,
    showsDate: Bool,
    showsWeekday: Bool,
    locale: Locale = .autoupdatingCurrent,
    calendar: Calendar = .autoupdatingCurrent
) -> String {
    let timeFormatter = DateFormatter()
    timeFormatter.locale = locale
    timeFormatter.calendar = calendar
    timeFormatter.timeZone = calendar.timeZone
    timeFormatter.dateStyle = .none
    timeFormatter.timeStyle = showsSeconds ? .medium : .short

    let dateLines = WorkspaceSidebarExpandedClockDateLines(
        date: date,
        locale: locale,
        calendar: calendar
    )
    var parts = [timeFormatter.string(from: date)]
    if showsWeekday {
        parts.append(dateLines.weekday)
    }
    if showsDate {
        parts.append(dateLines.monthAndDay)
    }
    return parts.joined(separator: ", ")
}
