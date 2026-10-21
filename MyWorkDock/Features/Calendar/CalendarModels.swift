import Foundation

enum CalendarMode: String, CaseIterable, Identifiable {
    case month, week, day

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// One entry of the account's calendar list.
struct CalendarInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var color: UInt32
    /// Google's own "shown in the calendar UI" flag: where visibility starts before the user changes it here.
    var selected: Bool
    /// freeBusyReader calendars carry no event titles.
    var busyOnly = false
}

struct CalendarEvent: Identifiable, Equatable {
    /// `<calendar id>|<event id>`: the same event can arrive in two fetched ranges, and in two calendars.
    var id: String
    var calendarID: String
    var title: String
    /// Timed: the instants. All-day: local midnight of the first day and of the day after the last (exclusive end).
    var start: Date
    var end: Date
    var allDay: Bool
    var color: UInt32
    var declined = false
}

/// The few fields of a Google event the grids need; the request's `fields` mask asks for exactly these.
struct RawEvent: Decodable {
    struct When: Decodable {
        var date: String?
        var dateTime: String?
    }

    struct Attendee: Decodable {
        var email: String?
        var responseStatus: String?
        var isSelf: Bool?

        enum CodingKeys: String, CodingKey {
            case email, responseStatus
            case isSelf = "self"
        }
    }

    var id: String
    var status: String?
    var summary: String?
    var start: When?
    var end: When?
    var colorId: String?
    var attendees: [Attendee]?
}

enum EventParser {
    /// Google's 11 event colours (`colors.get`, event palette); an event without a `colorId` takes its calendar's colour.
    static let palette: [String: UInt32] = [
        "1": 0xA4BDFC, "2": 0x7AE7BF, "3": 0xDBADFF, "4": 0xFF887C, "5": 0xFBD75B, "6": 0xFFB878,
        "7": 0x46D6DB, "8": 0xE1E1E1, "9": 0x5484ED, "10": 0x51B749, "11": 0xDC2127,
    ]

    private static let plain = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// RFC 3339 with an offset or Z, with or without fractional seconds.
    static func instant(_ text: String) -> Date? { plain.date(from: text) ?? fractional.date(from: text) }

    /// `2026-10-21` as local midnight. All-day dates are floating: they never go through UTC.
    static func day(_ text: String, _ cal: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// nil for cancelled events and anything without a usable start.
    static func parse(_ raw: RawEvent, in calendar: CalendarInfo, cal: Calendar) -> CalendarEvent? {
        guard raw.status != "cancelled", let start = raw.start else { return nil }
        let allDay: Bool
        let from: Date
        let to: Date
        if let first = start.date.flatMap({ day($0, cal) }) {
            allDay = true
            from = first
            let exclusiveEnd = raw.end?.date.flatMap { day($0, cal) }
            to = exclusiveEnd.flatMap { $0 > first ? $0 : nil } ?? cal.date(byAdding: .day, value: 1, to: first) ?? first
        } else if let instant = start.dateTime.flatMap(instant) {
            allDay = false
            from = instant
            to = max(raw.end?.dateTime.flatMap(Self.instant) ?? instant, instant)
        } else {
            return nil
        }
        let declined = raw.attendees?.contains { ($0.isSelf == true || $0.email == calendar.id) && $0.responseStatus == "declined" } ?? false
        let title = raw.summary.flatMap { $0.isEmpty ? nil : $0 } ?? (calendar.busyOnly ? "Busy" : "(No title)")
        return CalendarEvent(id: "\(calendar.id)|\(raw.id)", calendarID: calendar.id, title: title, start: from, end: to, allDay: allDay,
                             color: raw.colorId.flatMap { palette[$0] } ?? calendar.color, declined: declined)
    }

    /// `#9fe1e7` → 0x9FE1E7.
    static func hex(_ text: String?) -> UInt32? {
        guard let text, text.hasPrefix("#") else { return nil }
        return UInt32(text.dropFirst(), radix: 16)
    }
}
