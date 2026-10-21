import Foundation

/// Sample content for snapshots and tests, like `SampleData` for the other tabs: "today" is Wed 21 Oct 2026, 10:30,
/// with four calendars (Holidays starts hidden, like a subscribed calendar Google leaves unticked).
enum CalendarSample {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        cal.timeZone = .current
        return cal
    }()

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    static let now = date(21, 10, 30)

    static let calendars = [
        CalendarInfo(id: "work", name: "Work", color: 0x4285F4, selected: true),
        CalendarInfo(id: "team", name: "Team", color: 0xF4511E, selected: true),
        CalendarInfo(id: "personal", name: "Personal", color: 0x33B679, selected: true),
        CalendarInfo(id: "holidays", name: "Holidays in India", color: 0x0B8043, selected: false),
    ]

    private static func color(_ id: String) -> UInt32 { calendars.first { $0.id == id }?.color ?? 0x4285F4 }

    private static func timed(_ calendarID: String, _ title: String, _ day: Int, _ from: (Int, Int), _ to: (Int, Int), declined: Bool = false) -> CalendarEvent {
        CalendarEvent(id: "\(calendarID)|\(title)-\(day)", calendarID: calendarID, title: title, start: date(day, from.0, from.1), end: date(day, to.0, to.1),
                      allDay: false, color: color(calendarID), declined: declined)
    }

    private static func allDay(_ calendarID: String, _ title: String, _ first: Int, _ last: Int, month: Int = 10) -> CalendarEvent {
        CalendarEvent(id: "\(calendarID)|\(title)-\(first)", calendarID: calendarID, title: title, start: date(first, month: month),
                      end: date(last + 1, month: month), allDay: true, color: color(calendarID))
    }

    static let events: [CalendarEvent] = [
        // Mon 19
        timed("work", "Standup", 19, (9, 30), (9, 45)), timed("work", "Sprint planning", 19, (10, 0), (11, 0)),
        timed("team", "Design sync", 19, (11, 30), (12, 0)), timed("personal", "Lunch", 19, (13, 0), (14, 0)),
        // Tue 20
        timed("work", "Standup", 20, (9, 30), (9, 45)), timed("work", "1:1 with Meera", 20, (10, 0), (10, 30)),
        timed("team", "Code review", 20, (10, 15), (11, 15)), timed("work", "Vendor demo", 20, (14, 0), (15, 0), declined: true),
        timed("personal", "Dentist", 20, (17, 0), (18, 0)), allDay("holidays", "Dussehera", 20, 20),
        // Wed 21 (today): three meetings overlap at 10:45
        timed("work", "Standup", 21, (9, 30), (9, 45)), timed("work", "Client call: Asaya rollout", 21, (10, 0), (11, 30)),
        timed("team", "Quarterly review prep", 21, (10, 30), (12, 0)), timed("work", "Hotfix triage", 21, (10, 45), (11, 15)),
        timed("personal", "Gym", 21, (18, 30), (19, 30)),
        // Thu 22 – Fri 23
        allDay("team", "Offsite", 22, 23), timed("work", "Standup", 22, (9, 30), (9, 45)), timed("work", "Demo prep", 22, (14, 0), (15, 30)),
        timed("team", "Team dinner", 22, (19, 30), (21, 30)),
        timed("work", "Standup", 23, (9, 30), (9, 45)),
        timed("work", "Quarterly roadmap review with finance, design and the whole platform team", 23, (11, 0), (12, 0)),
        timed("work", "Release 0.1.14", 23, (15, 0), (16, 0)),
        // Sat 24
        allDay("personal", "Birthday: Aarav", 24, 24),
        // The next week: a day busy enough for "+N more" in the month grid
        timed("work", "Sprint planning", 26, (10, 0), (11, 0)),
        timed("work", "Planning", 28, (10, 0), (11, 0)), timed("team", "Sync", 28, (11, 0), (11, 30)), timed("personal", "Lunch", 28, (12, 30), (13, 30)),
        timed("work", "Review", 28, (14, 0), (15, 0)), timed("work", "Interviews", 28, (16, 0), (17, 30)), timed("team", "Town hall", 28, (17, 0), (18, 0)),
        timed("work", "Retro", 30, (16, 0), (17, 0)), allDay("work", "Payroll", 30, 30),
    ]

    /// One fetch per calendar covering the whole October grid (27 Sep – 31 Oct), so every view finds its data.
    static func chunks(cal: Calendar) -> [CalendarStore.Chunk] {
        calendars.map { calendar in
            CalendarStore.Chunk(calendarID: calendar.id, from: date(27, month: 9), to: date(1, month: 11),
                                events: events.filter { $0.calendarID == calendar.id }, fetchedAt: now)
        }
    }
}
