import SwiftUI

extension Geo.Cal {
    static let gridRadius: CGFloat = 14
    static let weekdayHeight: CGFloat = 20
    /// Month cell: the day number row, then the chips.
    static let cellHeader: CGFloat = 22
    static let chipHeight: CGFloat = 14
    static let chipGap: CGFloat = 1
    static let chipFont: CGFloat = 10.5
    static let todayCircle: CGFloat = 20
    /// Week and Day: the weekday + number header, the hour rows, the gutter with the hour labels.
    static let headerHeight: CGFloat = 40
    static let hourHeight: CGFloat = 40
    static let gutter: CGFloat = 46
    static let blockRadius: CGFloat = 5
    static let maxAllDayLanes = 3
}

private struct GridSurface: ViewModifier {
    @Environment(\.tokens) private var t

    func body(content: Content) -> some View {
        content
            .background(t.list)
            .clipShape(RoundedRectangle(cornerRadius: Geo.Cal.gridRadius))
            .overlay(RoundedRectangle(cornerRadius: Geo.Cal.gridRadius).strokeBorder(t.line, lineWidth: 1))
    }
}

private extension View {
    func gridSurface() -> some View { modifier(GridSurface()) }
}

/// The number of a day: today wears the tint circle.
private struct DayNumber: View {
    var day: Date
    var today: Bool
    var dim = false
    var cal: Calendar
    @Environment(\.tokens) private var t

    var body: some View {
        let number = cal.component(.day, from: day)
        // The first of a month says which month it is, like Google's grid.
        let text = number == 1 ? day.formatted(.dateTime.month(.abbreviated).day()) : "\(number)"
        Text(text)
            .font(Typo.ui(11.5, today ? .bold : .semibold))
            .foregroundStyle(today ? Tokens.onTint : dim ? t.faint : t.text2)
            .padding(.horizontal, today ? 0 : 3)
            .frame(minWidth: Geo.Cal.todayCircle, minHeight: Geo.Cal.todayCircle)
            .background(Capsule().fill(today ? t.accent : .clear))
    }
}

/// An event as one line in a month cell or the all-day strip: wide events are a tinted bar, timed ones a dot and a title.
private struct EventChip: View {
    var event: CalendarEvent
    @Environment(\.tokens) private var t

    var body: some View {
        let color = Color(hex: event.color)
        Group {
            if CalendarLayout.isWide(event) {
                Text(event.title)
                    .font(Typo.ui(Geo.Cal.chipFont, .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Geo.Cal.chipHeight)
                    .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(t.isDark ? 0.30 : 0.34)))
            } else {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(event.title).font(Typo.ui(Geo.Cal.chipFont, .medium)).lineLimit(1)
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Geo.Cal.chipHeight)
            }
        }
        .foregroundStyle(t.text)
        .strikethrough(event.declined)
        .opacity(event.declined ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.title + (event.declined ? ", declined" : ""))
    }
}

/// A chip that opens its event's sheet.
private struct ChipButton: View {
    var store: CalendarStore
    var event: CalendarEvent

    var body: some View {
        Button { store.select(event) } label: { EventChip(event: event) }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the event")
    }
}

// MARK: Month

struct CalendarMonthView: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t

    var body: some View {
        let days = store.visibleDays
        let events = store.visibleEvents
        let rows = max(1, days.count / 7)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(Typo.ui(10, .bold))
                        .tracking(0.6)
                        .foregroundStyle(t.faint)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Geo.Cal.weekdayHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
            GeometryReader { geo in
                let rowHeight = geo.size.height / CGFloat(rows)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                let day = days[row * 7 + column]
                                MonthCell(store: store, day: day, events: CalendarLayout.events(on: day, in: events, cal: store.cal), height: rowHeight)
                            }
                        }
                    }
                }
            }
        }
        .gridSurface()
    }
}

private struct MonthCell: View {
    var store: CalendarStore
    var day: Date
    var events: [CalendarEvent]
    var height: CGFloat
    @Environment(\.tokens) private var t

    var body: some View {
        let cal = store.cal
        let room = max(0, Int((height - Geo.Cal.cellHeader - 2) / (Geo.Cal.chipHeight + Geo.Cal.chipGap)))
        // With more events than lines the last line says how many are hidden.
        let shown = events.count > room ? max(0, room - 1) : events.count
        // The cell opens its day; the chips inside it are buttons of their own and open their event.
        VStack(alignment: .leading, spacing: Geo.Cal.chipGap) {
            DayNumber(day: day, today: cal.isDate(day, inSameDayAs: store.now()),
                      dim: !cal.isDate(day, equalTo: store.anchor, toGranularity: .month), cal: cal)
                .frame(height: Geo.Cal.cellHeader - 2, alignment: .leading)
            ForEach(events.prefix(shown)) { ChipButton(store: store, event: $0) }
            if events.count > shown {
                Text("+\(events.count - shown) more").font(Typo.ui(10, .semibold)).foregroundStyle(t.faint).padding(.leading, 4)
            }
        }
        .padding(.horizontal, 3)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) { Rectangle().fill(t.line).frame(width: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { store.openDay(day) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + ", \(events.count) event\(events.count == 1 ? "" : "s")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.openDay(day) }
    }
}

// MARK: Week and Day

/// Week (seven columns) and Day (one): weekday header, an all-day strip, then 24 hour rows that scroll, with overlapping
/// events side by side and a red line at the current time.
struct CalendarTimeGrid: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t
    @Environment(\.staticRender) private var staticRender

    private struct ScrollKey: Equatable {
        var first: Date?
        var mode: CalendarMode
        var hour: Int
    }

    var body: some View {
        let days = store.visibleDays
        let events = store.visibleEvents
        let perDay = days.map { CalendarLayout.events(on: $0, in: events, cal: store.cal) }
        let wide = perDay.map { $0.filter(CalendarLayout.isWide) }
        let lanes = min(wide.map(\.count).max() ?? 0, Geo.Cal.maxAllDayLanes)
        VStack(spacing: 0) {
            headers(days)
            if lanes > 0 { allDayStrip(wide, lanes: lanes) }
            Rectangle().fill(t.line).frame(height: 1)
            hours(days, perDay)
        }
        .gridSurface()
    }

    private func headers(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Geo.Cal.gutter)
            ForEach(days, id: \.self) { day in
                let today = store.cal.isDate(day, inSameDayAs: store.now())
                VStack(spacing: 1) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(Typo.ui(10, .bold))
                        .tracking(0.6)
                        .foregroundStyle(today ? t.ink : t.faint)
                    Text(day.formatted(.dateTime.day()))
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(today ? Tokens.onTint : t.text)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(today ? t.accent : .clear))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: Geo.Cal.headerHeight)
    }

    private func allDayStrip(_ wide: [[CalendarEvent]], lanes: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day")
                .font(Typo.ui(9.5))
                .foregroundStyle(t.faint)
                .frame(width: Geo.Cal.gutter - 6, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.top, 2)
            ForEach(Array(wide.enumerated()), id: \.offset) { _, events in
                let shown = events.count > lanes ? lanes - 1 : events.count
                VStack(spacing: Geo.Cal.chipGap) {
                    ForEach(events.prefix(shown)) { ChipButton(store: store, event: $0) }
                    if events.count > shown {
                        Text("+\(events.count - shown) more").font(Typo.ui(10, .semibold)).foregroundStyle(t.faint)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .top)
                .overlay(alignment: .leading) { Rectangle().fill(t.line).frame(width: 1) }
            }
        }
        .padding(.vertical, 3)
        .frame(height: CGFloat(lanes) * (Geo.Cal.chipHeight + Geo.Cal.chipGap) + 6, alignment: .top)
    }

    private func hours(_ days: [Date], _ perDay: [[CalendarEvent]]) -> some View {
        let height = Geo.Cal.hourHeight
        let first = startHour(days, perDay)
        let content = ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 0) {
                        Text(hour == 0 ? "" : hourLabel(hour))
                            .font(Typo.ui(10))
                            .foregroundStyle(t.faint)
                            .frame(width: Geo.Cal.gutter - 6, alignment: .trailing)
                            .padding(.trailing, 6)
                            .offset(y: -6)
                        Rectangle().fill(t.line).frame(height: 1)
                    }
                    .frame(height: height, alignment: .top)
                    .id(hour)
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: Geo.Cal.gutter)
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in column(day, perDay[index]) }
            }
        }
        .frame(height: 24 * height)
        return Group {
            if staticRender {
                // ImageRenderer cannot draw a ScrollView: show the window a real one would open on.
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { content.offset(y: -CGFloat(first) * height) }
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) { content }
                        .task(id: ScrollKey(first: days.first, mode: store.mode, hour: first)) {
                            await Task.yield()
                            proxy.scrollTo(first, anchor: .top)
                        }
                }
            }
        }
    }

    private func column(_ day: Date, _ events: [CalendarEvent]) -> some View {
        let slots = CalendarLayout.slots(of: events, on: day, cal: store.cal)
        let today = store.cal.isDate(day, inSameDayAs: store.now())
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(slots) { slot in
                    let lane = geo.size.width / CGFloat(slot.columns)
                    Button { store.select(slot.event) } label: {
                        EventBlock(event: slot.event, height: CGFloat(slot.endMinute - slot.startMinute) / 60 * Geo.Cal.hourHeight - 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the event")
                    .frame(width: max(0, lane - 2), height: max(0, CGFloat(slot.endMinute - slot.startMinute) / 60 * Geo.Cal.hourHeight - 1))
                    .offset(x: CGFloat(slot.column) * lane + 1, y: CGFloat(slot.startMinute) / 60 * Geo.Cal.hourHeight)
                }
                if today { NowLine(store: store) }
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(t.line).frame(width: 1) }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = store.cal.date(bySettingHour: hour, minute: 0, second: 0, of: store.visibleDays.first ?? store.now()) ?? store.now()
        return date.formatted(.dateTime.hour())
    }

    /// Where the hour grid opens: an hour before now when today is on screen, else an hour before the earliest timed event (9 am without any).
    private func startHour(_ days: [Date], _ perDay: [[CalendarEvent]]) -> Int {
        let cal = store.cal
        let hour: Int
        if days.contains(where: { cal.isDate($0, inSameDayAs: store.now()) }) {
            hour = cal.component(.hour, from: store.now()) - 1
        } else {
            let earliest = perDay.flatMap { $0 }.filter { !CalendarLayout.isWide($0) }.map { cal.component(.hour, from: $0.start) }.min()
            hour = (earliest ?? 9) - 1
        }
        return min(max(hour, 0), 17)
    }
}

/// A timed event in the hour grid: tinted fill, a bar in the calendar's colour on the left.
private struct EventBlock: View {
    var event: CalendarEvent
    var height: CGFloat
    @Environment(\.tokens) private var t

    var body: some View {
        let color = Color(hex: event.color)
        let tall = height >= 34
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title).font(Typo.ui(11, .semibold)).lineLimit(tall ? 2 : 1)
            if tall {
                Text((event.start..<max(event.end, event.start)).formatted(Date.IntervalFormatStyle(time: .shortened)))
                    .font(Typo.ui(10)).foregroundStyle(t.text2).lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(t.text)
        .strikethrough(event.declined)
        .background(color.opacity(t.isDark ? 0.28 : 0.34))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Geo.Cal.blockRadius))
        .opacity(event.declined ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), " + (event.start..<max(event.end, event.start)).formatted(Date.IntervalFormatStyle(time: .shortened)))
    }
}

/// The red line at the current time, with its dot; moves every minute.
private struct NowLine: View {
    var store: CalendarStore

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let parts = store.cal.dateComponents([.hour, .minute], from: store.now())
            let minutes = CGFloat((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            HStack(spacing: 0) {
                Circle().fill(Fixed.danger).frame(width: 8, height: 8).offset(x: -4)
                Rectangle().fill(Fixed.danger).frame(height: 1.5)
            }
            .offset(y: minutes / 60 * Geo.Cal.hourHeight - 4)
            .allowsHitTesting(false)
        }
    }
}
