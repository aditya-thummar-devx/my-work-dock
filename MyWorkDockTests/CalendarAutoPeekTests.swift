import XCTest
@testable import MyWorkDock

@MainActor
final class CalendarAutoPeekTests: XCTestCase {
    private var model: NotchModel!
    private var store: CalendarStore!

    override func setUp() async throws {
        model = NotchModel(sample: true)
        store = model.calendar
    }

    func testCalendarPeekStateProperties() {
        let now = Date()
        let start = now.addingTimeInterval(300) // in 5 min
        let end = start.addingTimeInterval(1800) // 30 min long
        let item = CalendarPeekItem(eventID: "ev1", title: "Design sync", start: start, end: end,
                                    meetURL: URL(string: "https://meet.google.com/xyz")!,
                                    meetName: "Google Meet")

        let headsUp = CalendarPeekState.headsUp(item: item, minutesLeft: 5)
        XCTAssertEqual(headsUp.item.title, "Design sync")
        XCTAssertTrue(headsUp.isVisible)
        XCTAssertFalse(headsUp.isShrunk)

        let live = CalendarPeekState.live(item: item, minutesLeft: 30)
        XCTAssertEqual(live.item.title, "Design sync")
        XCTAssertTrue(live.isVisible)
        XCTAssertFalse(live.isShrunk)

        let shrunkCollapsed = CalendarPeekState.shrunk(item: item, reExpanded: false)
        XCTAssertEqual(shrunkCollapsed.item.title, "Design sync")
        XCTAssertFalse(shrunkCollapsed.isVisible)
        XCTAssertTrue(shrunkCollapsed.isShrunk)

        let shrunkExpanded = CalendarPeekState.shrunk(item: item, reExpanded: true)
        XCTAssertTrue(shrunkExpanded.isVisible)
        XCTAssertTrue(shrunkExpanded.isShrunk)
    }

    func testNotchModeWithCalendarPeekState() {
        XCTAssertEqual(model.mode, .idle)
        
        let item = CalendarPeekItem(eventID: "ev1", title: "Standup", start: Date(), end: Date().addingTimeInterval(900),
                                    meetURL: URL(string: "https://meet.google.com/abc")!,
                                    meetName: "Meet")
        
        model.setCalendarPeekState(.headsUp(item: item, minutesLeft: 3))
        XCTAssertEqual(model.mode, .peek)

        model.setCalendarPeekState(nil)
        XCTAssertEqual(model.mode, .idle)
    }

    func testShrinkAndDismissCalendarPeek() {
        let item = CalendarPeekItem(eventID: "ev1", title: "Standup", start: Date(), end: Date().addingTimeInterval(900),
                                    meetURL: URL(string: "https://meet.google.com/abc")!,
                                    meetName: "Meet")
        
        model.setCalendarPeekState(.headsUp(item: item, minutesLeft: 3))
        XCTAssertEqual(model.mode, .peek)

        // Dismiss clears peek
        model.dismissCalendarPeek()
        XCTAssertNil(model.calendarPeekState)
        XCTAssertEqual(model.mode, .idle)
    }

    func testThresholdClamping() {
        model.setCalendarAutoPeekThreshold(1)
        XCTAssertEqual(model.calendarAutoPeekThreshold, 2) // minimum 2 min

        model.setCalendarAutoPeekThreshold(45)
        XCTAssertEqual(model.calendarAutoPeekThreshold, 30) // maximum 30 min

        model.setCalendarAutoPeekThreshold(10)
        XCTAssertEqual(model.calendarAutoPeekThreshold, 10)
    }

    func testSettingsToggle() {
        XCTAssertFalse(model.calendarAutoPeekEnabled)
        model.setCalendarAutoPeekEnabled(true)
        XCTAssertTrue(model.calendarAutoPeekEnabled)
        model.setCalendarAutoPeekEnabled(false)
        XCTAssertFalse(model.calendarAutoPeekEnabled)
    }

    func testEventWithMeetURLPopulatedInParser() {
        let json = """
        {
            "id": "event_with_meet",
            "status": "confirmed",
            "summary": "Sync call",
            "start": { "dateTime": "2026-10-21T10:00:00Z" },
            "end": { "dateTime": "2026-10-21T10:30:00Z" },
            "hangoutLink": "https://meet.google.com/abc-def-ghi"
        }
        """.data(using: .utf8)!

        let raw = try! JSONDecoder().decode(RawEvent.self, from: json)
        let calendar = CalendarInfo(id: "work", name: "Work", color: 0x4285F4, selected: true)
        let event = EventParser.parse(raw, in: calendar, cal: .current)!

        XCTAssertEqual(event.title, "Sync call")
        XCTAssertEqual(event.meetURL, URL(string: "https://meet.google.com/abc-def-ghi"))
        XCTAssertEqual(event.meetName, "Google Meet")
    }

    func testEventWithConferenceDataVideoEntry() {
        let json = """
        {
            "id": "event_zoom",
            "status": "confirmed",
            "summary": "Zoom call",
            "start": { "dateTime": "2026-10-21T10:00:00Z" },
            "end": { "dateTime": "2026-10-21T10:30:00Z" },
            "conferenceData": {
                "conferenceSolution": { "name": "Zoom Meeting" },
                "entryPoints": [
                    { "entryPointType": "video", "uri": "https://zoom.us/j/123456" },
                    { "entryPointType": "phone", "uri": "tel:+12345678" }
                ]
            }
        }
        """.data(using: .utf8)!

        let raw = try! JSONDecoder().decode(RawEvent.self, from: json)
        let calendar = CalendarInfo(id: "work", name: "Work", color: 0x4285F4, selected: true)
        let event = EventParser.parse(raw, in: calendar, cal: .current)!

        XCTAssertEqual(event.title, "Zoom call")
        XCTAssertEqual(event.meetURL, URL(string: "https://zoom.us/j/123456"))
        XCTAssertEqual(event.meetName, "Zoom Meeting")
    }
}
