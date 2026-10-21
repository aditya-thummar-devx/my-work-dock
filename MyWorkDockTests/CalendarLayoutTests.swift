import XCTest
@testable import MyWorkDock

final class CalendarLayoutTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Kolkata", firstWeekday: Int = 1) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func date(_ cal: Calendar, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func timed(_ id: String, _ cal: Calendar, from: Date, to: Date) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", title: id, start: from, end: to, allDay: false, color: 0x4285F4)
    }

    private func allDay(_ id: String, _ cal: Calendar, _ first: Date, days: Int) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: "c", title: id, start: first, end: cal.date(byAdding: .day, value: days, to: first)!, allDay: true, color: 0x33B679)
    }

    // MARK: Days on screen

    func testMonthGridIsWholeWeeksFromTheFirstWeekday() {
        let sunday = calendar()
        let october = CalendarLayout.visibleDays(.month, around: date(sunday, 10, 21), cal: sunday)
        XCTAssertEqual(october.count, 35) // Thu 1 Oct leads with four days of September
        XCTAssertEqual(october.first, date(sunday, 9, 27))
        XCTAssertEqual(october.last, date(sunday, 10, 31))
        XCTAssertEqual(CalendarLayout.visibleDays(.month, around: date(sunday, 5, 10), cal: sunday).count, 42) // May 2026 needs six rows
        XCTAssertEqual(CalendarLayout.visibleDays(.month, around: date(sunday, 2, 10), cal: sunday).count, 28) // Feb 2026 starts on a Sunday: four rows

        let monday = calendar(firstWeekday: 2)
        let mondayOctober = CalendarLayout.visibleDays(.month, around: date(monday, 10, 21), cal: monday)
        XCTAssertEqual(mondayOctober.first, date(monday, 9, 28))
        XCTAssertEqual(mondayOctober.count, 35)
    }

    func testWeekAndDayFollowTheCalendar() {
        let sunday = calendar()
        let week = CalendarLayout.visibleDays(.week, around: date(sunday, 10, 21, 15), cal: sunday)
        XCTAssertEqual(week.first, date(sunday, 10, 18))
        XCTAssertEqual(week.last, date(sunday, 10, 24))
        let monday = calendar(firstWeekday: 2)
        XCTAssertEqual(CalendarLayout.visibleDays(.week, around: date(monday, 10, 21), cal: monday).first, date(monday, 10, 19))
        XCTAssertEqual(CalendarLayout.visibleDays(.day, around: date(sunday, 10, 21, 15, 45), cal: sunday), [date(sunday, 10, 21)])
    }

    func testRangeRunsFromTheFirstDayToTheEndOfTheLast() {
        let cal = calendar()
        let range = CalendarLayout.range(of: CalendarLayout.visibleDays(.week, around: date(cal, 10, 21), cal: cal), cal: cal)
        XCTAssertEqual(range.from, date(cal, 10, 18))
        XCTAssertEqual(range.to, date(cal, 10, 25))
    }

    func testShiftingByViewKeepsMonthEndsInRange() {
        let cal = calendar()
        XCTAssertEqual(CalendarLayout.shifted(date(cal, 1, 31), .month, by: 1, cal: cal), date(cal, 2, 28)) // clamps, never lands in March
        XCTAssertEqual(CalendarLayout.shifted(date(cal, 10, 21), .week, by: -1, cal: cal), date(cal, 10, 14))
        XCTAssertEqual(CalendarLayout.shifted(date(cal, 10, 31), .day, by: 1, cal: cal), date(cal, 11, 1))
    }

    // MARK: Events on a day

    func testEventsOnADayIncludeMultiDayAndMidnightCrossersButNotThoseThatEndAtMidnight() {
        let cal = calendar()
        let offsite = allDay("offsite", cal, date(cal, 10, 22), days: 2)
        let late = timed("late", cal, from: date(cal, 10, 22, 23), to: date(cal, 10, 23, 1))
        let ends = timed("ends", cal, from: date(cal, 10, 22, 22), to: date(cal, 10, 23))
        let all = [offsite, late, ends]
        XCTAssertEqual(CalendarLayout.events(on: date(cal, 10, 22), in: all, cal: cal).map(\.id), ["offsite", "ends", "late"])
        XCTAssertEqual(CalendarLayout.events(on: date(cal, 10, 23), in: all, cal: cal).map(\.id), ["offsite", "late"])
        XCTAssertEqual(CalendarLayout.events(on: date(cal, 10, 24), in: all, cal: cal).map(\.id), [])
        XCTAssertEqual(CalendarLayout.events(on: date(cal, 10, 21), in: all, cal: cal).map(\.id), [])
    }

    func testWideEventsComeFirstLongestFirstThenTimedByStart() {
        let cal = calendar()
        let day = date(cal, 10, 22)
        let short = allDay("short", cal, day, days: 1)
        let long = allDay("long", cal, day, days: 3)
        let early = timed("early", cal, from: date(cal, 10, 22, 8), to: date(cal, 10, 22, 9))
        let late = timed("late", cal, from: date(cal, 10, 22, 17), to: date(cal, 10, 22, 18))
        XCTAssertEqual(CalendarLayout.events(on: day, in: [late, short, early, long], cal: cal).map(\.id), ["long", "short", "early", "late"])
    }

    func testAZeroLengthEventAtMidnightStillShowsOnItsDay() {
        let cal = calendar()
        let marker = timed("marker", cal, from: date(cal, 10, 22), to: date(cal, 10, 22))
        XCTAssertEqual(CalendarLayout.events(on: date(cal, 10, 22), in: [marker], cal: cal).map(\.id), ["marker"])
        XCTAssertEqual(CalendarLayout.events(on: date(cal, 10, 21), in: [marker], cal: cal).map(\.id), [])
    }

    // MARK: Hour grid

    func testOverlapsSplitIntoColumnsAndLaterEventsStartANewCluster() {
        let cal = calendar()
        let day = date(cal, 10, 21)
        let events = [
            timed("a", cal, from: date(cal, 10, 21, 10), to: date(cal, 10, 21, 11, 30)),
            timed("b", cal, from: date(cal, 10, 21, 10, 30), to: date(cal, 10, 21, 12)),
            timed("c", cal, from: date(cal, 10, 21, 10, 45), to: date(cal, 10, 21, 11, 15)),
            timed("d", cal, from: date(cal, 10, 21, 14), to: date(cal, 10, 21, 15)),
        ]
        let slots = CalendarLayout.slots(of: events, on: day, cal: cal)
        let byID = Dictionary(uniqueKeysWithValues: slots.map { ($0.event.id, $0) })
        XCTAssertEqual([byID["a"]!.column, byID["b"]!.column, byID["c"]!.column], [0, 1, 2])
        XCTAssertEqual([byID["a"]!.columns, byID["b"]!.columns, byID["c"]!.columns], [3, 3, 3])
        XCTAssertEqual(byID["d"]!.column, 0)
        XCTAssertEqual(byID["d"]!.columns, 1) // the afternoon meeting does not inherit the morning's three columns
        XCTAssertEqual(byID["a"]!.startMinute, 600)
        XCTAssertEqual(byID["a"]!.endMinute, 690)
    }

    func testAFreedColumnIsReused() {
        let cal = calendar()
        let events = [
            timed("a", cal, from: date(cal, 10, 21, 9), to: date(cal, 10, 21, 10)),
            timed("b", cal, from: date(cal, 10, 21, 9, 30), to: date(cal, 10, 21, 10, 30)),
            timed("c", cal, from: date(cal, 10, 21, 10), to: date(cal, 10, 21, 11)),
        ]
        let slots = CalendarLayout.slots(of: events, on: date(cal, 10, 21), cal: cal)
        XCTAssertEqual(slots.map(\.column), [0, 1, 0]) // c starts as a ends
        XCTAssertEqual(Set(slots.map(\.columns)), [2])
    }

    func testShortEventsAreDrawnAtAMinimumHeightAndShareColumnsWithWhatTheyTouch() {
        let cal = calendar()
        let events = [
            timed("blip", cal, from: date(cal, 10, 21, 9), to: date(cal, 10, 21, 9, 5)),
            timed("next", cal, from: date(cal, 10, 21, 9, 10), to: date(cal, 10, 21, 10)),
        ]
        let slots = CalendarLayout.slots(of: events, on: date(cal, 10, 21), cal: cal, minimumMinutes: 30)
        XCTAssertEqual(slots.first { $0.event.id == "blip" }?.endMinute, 570) // 9:30
        XCTAssertEqual(slots.map(\.columns), [2, 2]) // the 5-minute blip is drawn over 9:10, so they cannot share a column
    }

    func testEventsAreClippedToEachDayTheyCross() {
        let cal = calendar()
        let night = timed("night", cal, from: date(cal, 10, 21, 22), to: date(cal, 10, 22, 2))
        let first = CalendarLayout.slots(of: [night], on: date(cal, 10, 21), cal: cal)
        let second = CalendarLayout.slots(of: [night], on: date(cal, 10, 22), cal: cal)
        XCTAssertEqual([first[0].startMinute, first[0].endMinute], [1320, 1440])
        XCTAssertEqual([second[0].startMinute, second[0].endMinute], [0, 120])
        XCTAssertTrue(CalendarLayout.slots(of: [night], on: date(cal, 10, 23), cal: cal).isEmpty)
    }

    func testAllDayAndDayLongEventsStayOutOfTheHourGrid() {
        let cal = calendar()
        let day = date(cal, 10, 21)
        let wide = [allDay("trip", cal, day, days: 2), timed("conference", cal, from: date(cal, 10, 21, 9), to: date(cal, 10, 22, 9))]
        XCTAssertTrue(CalendarLayout.slots(of: wide, on: day, cal: cal).isEmpty)
        XCTAssertTrue(wide.allSatisfy(CalendarLayout.isWide))
    }

    func testDaylightSavingDaysKeepWallClockRows() {
        let newYork = calendar("America/New_York")
        // Sun 1 Nov 2026 has 25 hours; Sun 8 Mar 2026 has 23. The rows must still line up with the hour labels.
        let fall = timed("fall", newYork, from: date(newYork, 11, 1, 10), to: date(newYork, 11, 1, 11))
        let spring = timed("spring", newYork, from: date(newYork, 3, 8, 3), to: date(newYork, 3, 8, 4))
        XCTAssertEqual(CalendarLayout.slots(of: [fall], on: date(newYork, 11, 1), cal: newYork).map { [$0.startMinute, $0.endMinute] }, [[600, 660]])
        XCTAssertEqual(CalendarLayout.slots(of: [spring], on: date(newYork, 3, 8), cal: newYork).map { [$0.startMinute, $0.endMinute] }, [[180, 240]])
        XCTAssertEqual(CalendarLayout.visibleDays(.week, around: date(newYork, 11, 1), cal: newYork).count, 7)
        XCTAssertEqual(CalendarLayout.visibleDays(.week, around: date(newYork, 11, 1), cal: newYork).first, date(newYork, 11, 1)) // no day lost or doubled
    }
}
