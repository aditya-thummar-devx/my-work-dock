import Foundation

/// Pure calendar maths for the grids: which days are on screen, which events touch a day, and how the timed ones share
/// the hour grid. Everything takes the `Calendar` so first weekday, time zone and DST come from one place.
enum CalendarLayout {
    /// The days on screen: the month grid (whole weeks, 5 or 6 rows), one week, or one day.
    static func visibleDays(_ mode: CalendarMode, around anchor: Date, cal: Calendar) -> [Date] {
        switch mode {
        case .day:
            return [cal.startOfDay(for: anchor)]
        case .week:
            return days(from: startOfWeek(anchor, cal), count: 7, cal)
        case .month:
            let monthStart = cal.dateInterval(of: .month, for: anchor)?.start ?? cal.startOfDay(for: anchor)
            let first = startOfWeek(monthStart, cal)
            let lead = cal.dateComponents([.day], from: first, to: monthStart).day ?? 0
            let length = cal.range(of: .day, in: .month, for: anchor)?.count ?? 30
            return days(from: first, count: (lead + length + 6) / 7 * 7, cal)
        }
    }

    /// What one fetch must cover: from the first visible day to the end of the last.
    static func range(of days: [Date], cal: Calendar) -> (from: Date, to: Date) {
        let first = days.first ?? Date()
        let last = days.last ?? first
        return (first, cal.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    static func shifted(_ anchor: Date, _ mode: CalendarMode, by steps: Int, cal: Calendar) -> Date {
        let unit: Calendar.Component = mode == .month ? .month : mode == .week ? .weekOfYear : .day
        return cal.date(byAdding: unit, value: steps, to: anchor) ?? anchor
    }

    static func startOfWeek(_ date: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    private static func days(from first: Date, count: Int, _ cal: Calendar) -> [Date] {
        (0..<count).map { cal.date(byAdding: .day, value: $0, to: first) ?? first }
    }

    /// All-day events, and anything 24 h or longer, live in the all-day strip instead of the hour grid.
    static func isWide(_ event: CalendarEvent) -> Bool { event.allDay || event.end.timeIntervalSince(event.start) >= 86_400 }

    /// Events touching `day` (a local midnight): wide ones first, longest first, then by start.
    static func events(on day: Date, in events: [CalendarEvent], cal: Calendar) -> [CalendarEvent] {
        let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
        return events
            .filter { $0.start < next && ($0.end > day || ($0.start == $0.end && $0.start >= day)) }
            .sorted { a, b in
                let (aWide, bWide) = (isWide(a), isWide(b))
                if aWide != bWide { return aWide }
                if aWide, a.end.timeIntervalSince(a.start) != b.end.timeIntervalSince(b.start) {
                    return a.end.timeIntervalSince(a.start) > b.end.timeIntervalSince(b.start)
                }
                return (a.start, a.title) < (b.start, b.title)
            }
    }

    /// A timed event as it sits in one day's hour grid. Minutes are wall-clock from that day's midnight, so the rows line up
    /// with the hour labels on 23 h and 25 h days too.
    struct Slot: Equatable, Identifiable {
        var event: CalendarEvent
        var startMinute: Int
        var endMinute: Int
        /// Which of `columns` side-by-side lanes it takes.
        var column: Int
        var columns: Int
        var id: String { event.id }
    }

    /// The timed events of `day`, clipped to it, with overlapping ones split into side-by-side columns. Events that overlap,
    /// even through the minimum height a 5-minute event is drawn at, share their cluster's columns.
    /// ponytail: an event never widens past its own column when its right neighbours are free; Google does that.
    static func slots(of events: [CalendarEvent], on day: Date, cal: Calendar, minimumMinutes: Int = 30) -> [Slot] {
        let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
        func minutes(_ date: Date) -> Int {
            let parts = cal.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        var items: [(event: CalendarEvent, start: Int, end: Int)] = []
        for event in events where !isWide(event) && event.start < next && (event.end > day || event.start >= day) {
            let start = event.start <= day ? 0 : minutes(event.start)
            let end = event.end >= next ? 1440 : minutes(event.end)
            items.append((event, start, min(1440, max(end, start + minimumMinutes))))
        }
        items.sort { ($0.start, -$0.end) < ($1.start, -$1.end) }

        var slots: [Slot] = []
        var cluster: [(event: CalendarEvent, start: Int, end: Int, column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0
        func flush() {
            let width = columnEnds.count
            slots += cluster.map { Slot(event: $0.event, startMinute: $0.start, endMinute: $0.end, column: $0.column, columns: width) }
            cluster = []
            columnEnds = []
            clusterEnd = 0
        }
        for item in items {
            if !cluster.isEmpty, item.start >= clusterEnd { flush() }
            let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(item.end) } else { columnEnds[column] = item.end }
            cluster.append((item.event, item.start, item.end, column))
            clusterEnd = max(clusterEnd, item.end)
        }
        flush()
        return slots
    }
}
