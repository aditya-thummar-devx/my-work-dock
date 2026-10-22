import XCTest
@testable import MyWorkDock

final class CalendarParseTests: XCTestCase {
    private var cal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private let work = CalendarInfo(id: "me@devxlabs.ai", name: "Work", color: 0x4285F4, selected: true)

    private func parse(_ json: String, in calendar: CalendarInfo? = nil) throws -> CalendarEvent? {
        let raw = try JSONDecoder().decode(RawEvent.self, from: Data(json.utf8))
        return EventParser.parse(raw, in: calendar ?? work, cal: cal)
    }

    func testTimedEventKeepsItsInstantsAndTakesTheCalendarColour() throws {
        let event = try XCTUnwrap(parse(#"{"id":"e1","summary":"Standup","start":{"dateTime":"2026-10-21T09:30:00+05:30"},"end":{"dateTime":"2026-10-21T09:45:00+05:30"}}"#))
        XCTAssertEqual(event.id, "me@devxlabs.ai|e1")
        XCTAssertEqual(event.title, "Standup")
        XCTAssertFalse(event.allDay)
        XCTAssertEqual(event.start, cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9, minute: 30)))
        XCTAssertEqual(event.end.timeIntervalSince(event.start), 900)
        XCTAssertEqual(event.color, 0x4285F4)
    }

    func testOffsetsFromOtherZonesAndFractionalSecondsAreInstants() throws {
        let zulu = try XCTUnwrap(parse(#"{"id":"e","start":{"dateTime":"2026-10-21T04:00:00Z"},"end":{"dateTime":"2026-10-21T05:00:00.000Z"}}"#))
        XCTAssertEqual(zulu.start, cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9, minute: 30))) // 04:00Z is 09:30 in Kolkata
        XCTAssertEqual(zulu.end.timeIntervalSince(zulu.start), 3600)
        let west = try XCTUnwrap(parse(#"{"id":"e","start":{"dateTime":"2026-10-21T10:00:00-07:00"},"end":{"dateTime":"2026-10-21T11:00:00-07:00"}}"#))
        XCTAssertEqual(west.start, ISO8601DateFormatter().date(from: "2026-10-21T17:00:00Z"))
    }

    func testAllDayEventsAreFloatingDatesWithAnExclusiveEnd() throws {
        let trip = try XCTUnwrap(parse(#"{"id":"t","summary":"Offsite","start":{"date":"2026-10-22"},"end":{"date":"2026-10-24"}}"#))
        XCTAssertTrue(trip.allDay)
        XCTAssertEqual(trip.start, cal.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        XCTAssertEqual(trip.end, cal.date(from: DateComponents(year: 2026, month: 10, day: 24))) // covers 22 and 23, not 24
        let oneDay = try XCTUnwrap(parse(#"{"id":"b","summary":"Birthday","start":{"date":"2026-10-24"}}"#))
        XCTAssertEqual(oneDay.end, cal.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        let backwards = try XCTUnwrap(parse(#"{"id":"x","start":{"date":"2026-10-24"},"end":{"date":"2026-10-24"}}"#))
        XCTAssertEqual(backwards.end, cal.date(from: DateComponents(year: 2026, month: 10, day: 25))) // never shorter than a day
    }

    func testCancelledAndUnusableEventsAreDropped() throws {
        XCTAssertNil(try parse(#"{"id":"c","status":"cancelled","start":{"dateTime":"2026-10-21T09:30:00Z"}}"#))
        XCTAssertNil(try parse(#"{"id":"n"}"#))
        XCTAssertNil(try parse(#"{"id":"j","start":{"dateTime":"yesterday"}}"#))
        XCTAssertNil(try parse(#"{"id":"j","start":{"date":"soon"}}"#))
    }

    func testEndBeforeStartCollapsesToAMarker() throws {
        let event = try XCTUnwrap(parse(#"{"id":"e","start":{"dateTime":"2026-10-21T10:00:00Z"},"end":{"dateTime":"2026-10-21T09:00:00Z"}}"#))
        XCTAssertEqual(event.end, event.start)
    }

    func testEventColourBeatsTheCalendarColourAndUnknownIdsFallBack() throws {
        XCTAssertEqual(try parse(#"{"id":"e","colorId":"11","start":{"dateTime":"2026-10-21T09:30:00Z"}}"#)?.color, 0xDC2127)
        XCTAssertEqual(try parse(#"{"id":"e","colorId":"99","start":{"dateTime":"2026-10-21T09:30:00Z"}}"#)?.color, 0x4285F4)
    }

    func testDeclinedMeansTheViewedCalendarSaidNo() throws {
        let mine = try parse(#"{"id":"e","start":{"dateTime":"2026-10-21T09:30:00Z"},"attendees":[{"email":"boss@x.com","responseStatus":"accepted"},{"email":"me@devxlabs.ai","self":true,"responseStatus":"declined"}]}"#)
        XCTAssertEqual(mine?.declined, true)
        let other = try parse(#"{"id":"e","start":{"dateTime":"2026-10-21T09:30:00Z"},"attendees":[{"email":"boss@x.com","responseStatus":"declined"},{"email":"me@devxlabs.ai","self":true,"responseStatus":"accepted"}]}"#)
        XCTAssertEqual(other?.declined, false) // someone else declining is not me declining
        let byEmail = try parse(#"{"id":"e","start":{"dateTime":"2026-10-21T09:30:00Z"},"attendees":[{"email":"me@devxlabs.ai","responseStatus":"declined"}]}"#)
        XCTAssertEqual(byEmail?.declined, true)
    }

    func testTitlesFallBackToBusyForFreeBusyCalendarsAndNoTitleOtherwise() throws {
        let busyCalendar = CalendarInfo(id: "colleague", name: "Colleague", color: 0xF4511E, selected: true, busyOnly: true)
        XCTAssertEqual(try parse(#"{"id":"e","start":{"dateTime":"2026-10-21T09:30:00Z"}}"#, in: busyCalendar)?.title, "Busy")
        XCTAssertEqual(try parse(#"{"id":"e","summary":"","start":{"dateTime":"2026-10-21T09:30:00Z"}}"#)?.title, "(No title)")
    }

    func testHexColours() {
        XCTAssertEqual(EventParser.hex("#9fe1e7"), 0x9FE1E7)
        XCTAssertNil(EventParser.hex("blue"))
        XCTAssertNil(EventParser.hex(nil))
    }
}
