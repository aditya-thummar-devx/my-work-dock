import XCTest
@testable import MyWorkDock

final class RecurrenceTests: XCTestCase {
    private var cal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func describe(_ rule: String...) -> String {
        // Wed 21 Oct 2026
        Recurrence.describe(rule, start: cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))!, cal: cal)
    }

    func testDailyAndWeekly() {
        XCTAssertEqual(describe("RRULE:FREQ=DAILY"), "Daily")
        XCTAssertEqual(describe("RRULE:FREQ=DAILY;INTERVAL=3"), "Every 3 days")
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;BYDAY=WE"), "Weekly on Wednesday")
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"), "Weekly on Monday, Wednesday, Friday")
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU"), "Every 2 weeks on Tuesday")
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY"), "Weekly on Wednesday") // no BYDAY: the start's weekday
    }

    func testEveryWeekdayIsRecognisedInAnyOrder() {
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"), "Every weekday")
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;BYDAY=FR,TH,WE,TU,MO"), "Every weekday")
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TU,WE,TH,FR"), "Every 2 weeks on Monday, Tuesday, Wednesday, Thursday, Friday")
    }

    func testMonthlyByDateAndByOrdinalWeekday() {
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY"), "Monthly on day 21")
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY;BYMONTHDAY=5"), "Monthly on day 5")
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY;BYDAY=3WE"), "Monthly on the third Wednesday")
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY;BYDAY=-1FR"), "Monthly on the last Friday")
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY;INTERVAL=3;BYDAY=1MO"), "Every 3 months on the first Monday")
    }

    func testYearlyAndEndings() {
        XCTAssertTrue(describe("RRULE:FREQ=YEARLY").hasPrefix("Annually on "))
        XCTAssertTrue(describe("RRULE:FREQ=YEARLY").contains("21"))
        XCTAssertEqual(describe("RRULE:FREQ=WEEKLY;BYDAY=WE;COUNT=5"), "Weekly on Wednesday, 5 times")
        XCTAssertEqual(describe("RRULE:FREQ=DAILY;COUNT=1"), "Daily, 1 time")
        let until = describe("RRULE:FREQ=WEEKLY;BYDAY=WE;UNTIL=20261231T183000Z")
        XCTAssertTrue(until.hasPrefix("Weekly on Wednesday, until ") && until.contains("2026"))
    }

    func testUnknownRulesAndMissingRulesReadRepeats() {
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY;BYDAY=MO,TU;BYSETPOS=1"), "Repeats")
        XCTAssertEqual(describe("RRULE:FREQ=HOURLY"), "Repeats")
        XCTAssertEqual(describe("RRULE:FREQ=MONTHLY;BYDAY=WE"), "Repeats") // every Wednesday of the month: no wording for it
        XCTAssertEqual(describe("EXDATE:20261028T043000Z"), "Repeats")
        XCTAssertEqual(Recurrence.describe([], start: Date(), cal: cal), "Repeats")
    }

    func testOtherLinesAroundTheRuleAreIgnored() {
        XCTAssertEqual(describe("EXDATE;TZID=Asia/Kolkata:20261028T100000", "RRULE:FREQ=WEEKLY;BYDAY=WE", "RDATE:20261101T100000Z"), "Weekly on Wednesday")
    }
}

final class RichTextTests: XCTestCase {
    private func plain(_ html: String) -> String { String(RichText.attributed(html: html).characters) }

    func testLineBreaksBulletsAndParagraphs() {
        XCTAssertEqual(plain("Agenda<br>one<br/>two"), "Agenda\none\ntwo")
        XCTAssertEqual(plain("<ul><li>one</li><li>two</li></ul>"), "• one\n• two")
        XCTAssertEqual(plain("<p>First</p><p>Second</p>"), "First\nSecond")
        XCTAssertEqual(plain("a<br><br><br><br>b"), "a\n\nb") // never a wider gap than one blank line
        XCTAssertEqual(plain("end<br><br>"), "end") // nothing trails
        XCTAssertEqual(plain("plain\r\ntext\nstays"), "plain\ntext\nstays") // text from other tools keeps its own breaks
    }

    func testBoldItalicAndUnderlineAreKept() {
        let text = RichText.attributed(html: "plain <b>bold</b> <i>it</i> <u>un</u> <strong><em>both</em></strong>")
        func intent(_ word: String) -> InlinePresentationIntent? {
            text.runs.first { String(text[$0.range].characters).contains(word) }?.inlinePresentationIntent
        }
        XCTAssertNil(intent("plain"))
        XCTAssertEqual(intent("bold"), .stronglyEmphasized)
        XCTAssertEqual(intent("it"), .emphasized)
        XCTAssertEqual(intent("both"), [.stronglyEmphasized, .emphasized])
        XCTAssertNotNil(text.runs.first { String(text[$0.range].characters) == "un" }?.underlineStyle)
    }

    func testLinksKeepOnlyWebAndMailAddresses() {
        let links = RichText.attributed(html: #"<a href="https://x.com/a?b=1&amp;c=2">site</a> <a href='mailto:a@b.com'>mail</a> <a href="javascript:alert(1)">bad</a> <a href="file:///etc/passwd">file</a>"#)
        func link(_ word: String) -> URL? { links.runs.first { String(links[$0.range].characters).contains(word) }?.link }
        XCTAssertEqual(link("site"), URL(string: "https://x.com/a?b=1&c=2"))
        XCTAssertEqual(link("mail"), URL(string: "mailto:a@b.com"))
        XCTAssertNil(link("bad"))
        XCTAssertNil(link("file"))
    }

    func testBareAddressesBecomeLinks() {
        let text = RichText.attributed(html: "see https://example.com/doc now")
        XCTAssertEqual(text.runs.compactMap(\.link), [URL(string: "https://example.com/doc")!])
        let already = RichText.attributed(html: #"<a href="https://a.com">https://a.com</a>"#)
        XCTAssertEqual(already.runs.compactMap(\.link).count, 1) // an address inside a link is not linked twice
    }

    func testEntitiesAreDecodedAndStrayBracketsStayText() {
        XCTAssertEqual(plain("Tom &amp; Jerry &lt;3 &#33; &#x41; &quot;q&quot; a&nbsp;b"), "Tom & Jerry <3 ! A \"q\" a b")
        XCTAssertEqual(plain("1 < 2 and 3 > 2"), "1 < 2 and 3 > 2")
        XCTAssertEqual(plain("fish &chips; &"), "fish &chips; &") // an entity that is not one is left alone
    }

    func testScriptsAndStylesAreDroppedWithTheirContent() {
        XCTAssertEqual(plain("a<script>alert('x')</script>b<style>p{color:red}</style>c"), "abc")
        XCTAssertEqual(plain("<div class=\"x\"><span>text</span></div>"), "text")
    }

    func testVeryLongTextIsCutWithAnEllipsis() {
        let long = String(repeating: "word ", count: 40)
        XCTAssertEqual(plain(long), long) // under the default limit nothing is cut
        let limited = String(RichText.attributed(html: long, limit: 50).characters)
        XCTAssertTrue(limited.hasSuffix("…"))
        XCTAssertLessThan(limited.count, 60)
    }
}

final class EventDetailsTests: XCTestCase {
    private let work = CalendarInfo(id: "me@x.com", name: "Work", color: 0x4285F4, selected: true, defaultReminders: [10, 1440])

    private func make(_ json: String) throws -> EventDetails {
        EventDetails.make(try JSONDecoder().decode(RawDetails.self, from: Data(json.utf8)), calendar: work)
    }

    func testMeetLinkFromTheHangoutLinkOrTheConferenceEntryPoints() throws {
        let hangout = try make(#"{"hangoutLink":"https://meet.google.com/abc-defg-hij"}"#)
        XCTAssertEqual(hangout.meetURL, URL(string: "https://meet.google.com/abc-defg-hij"))
        XCTAssertEqual(hangout.meetName, "Google Meet")

        let conference = try make(#"{"conferenceData":{"conferenceSolution":{"name":"Zoom Meeting"},"entryPoints":[{"entryPointType":"video","uri":"https://zoom.us/j/1"},{"entryPointType":"phone","uri":"tel:+1-555-0100","label":"+1 555 0100","pin":"1234"},{"entryPointType":"phone","uri":"tel:+44-20-0000"}]}}"#)
        XCTAssertEqual(conference.meetURL, URL(string: "https://zoom.us/j/1"))
        XCTAssertEqual(conference.meetName, "Zoom Meeting")
        XCTAssertEqual(conference.phones, [EventDetails.Phone(number: "+1 555 0100", pin: "1234"), EventDetails.Phone(number: "+44-20-0000", pin: nil)])
        XCTAssertNil(try make("{}").meetURL)
    }

    func testOnlyWebLinksSurvive() throws {
        XCTAssertNil(try make(#"{"hangoutLink":"javascript:alert(1)","htmlLink":"file:///x"}"#).meetURL)
        let attachments = try make(#"{"attachments":[{"title":"Doc","fileUrl":"https://docs.google.com/d/1"},{"title":"Bad","fileUrl":"file:///etc/passwd"},{"fileUrl":"https://x.com/a/report.pdf"}]}"#).attachments
        XCTAssertEqual(attachments.map(\.title), ["Doc", "report.pdf"])
        XCTAssertEqual(try make(#"{"htmlLink":"https://www.google.com/calendar/event?eid=1"}"#).link, URL(string: "https://www.google.com/calendar/event?eid=1"))
    }

    func testGuestsPutTheOrganizerFirstLeaveRoomsOutAndNeedMoreThanOnePerson() throws {
        let details = try make(#"{"attendees":[{"email":"z@x.com","displayName":"Zed","responseStatus":"accepted"},{"email":"room@x.com","displayName":"Room 4","resource":true,"responseStatus":"accepted"},{"email":"me@x.com","self":true,"responseStatus":"tentative"},{"email":"o@x.com","displayName":"Olga","organizer":true,"responseStatus":"accepted"},{"email":"a@x.com","responseStatus":"declined","optional":true}]}"#)
        XCTAssertEqual(details.guests.map(\.name), ["Olga", "a@x.com", "me@x.com", "Zed"])
        XCTAssertEqual(details.guests.map(\.response), [.accepted, .declined, .tentative, .accepted])
        XCTAssertEqual(details.guests.first { $0.isMe }?.name, "me@x.com")
        XCTAssertTrue(details.guests.first { $0.name == "a@x.com" }?.optional == true)
        XCTAssertTrue(try make(#"{"attendees":[{"email":"me@x.com","self":true,"organizer":true}]}"#).guests.isEmpty) // alone on the invite
        XCTAssertEqual(try make(#"{"attendees":[{"email":"a@x.com","responseStatus":"maybe-someday"},{"email":"b@x.com"}]}"#).guests.map(\.response), [.needsAction, .needsAction])
    }

    func testGuestSummaryCountsEachAnswer() {
        let guests = [("a", EventDetails.Response.accepted), ("b", .accepted), ("c", .declined), ("d", .tentative), ("e", .needsAction)]
            .map { EventDetails.Guest(id: $0.0, name: $0.0, response: $0.1, organizer: false, optional: false, isMe: false) }
        XCTAssertEqual(EventDetails.summary(guests), "5 guests · 2 yes · 1 no · 1 maybe · 1 awaiting")
        XCTAssertEqual(EventDetails.summary(Array(guests.prefix(2))), "2 guests · 2 yes")
    }

    func testHiddenOrTruncatedGuestListsSayWhy() throws {
        XCTAssertEqual(try make(#"{"guestsCanSeeOtherGuests":false}"#).guestsNote, "The organizer keeps the guest list private.")
        XCTAssertEqual(try make(#"{"attendeesOmitted":true}"#).guestsNote, "Google cut the guest list short.")
        XCTAssertNil(try make("{}").guestsNote)
    }

    func testOrganizerIsNamedOnlyWhenItIsSomeoneElse() throws {
        XCTAssertEqual(try make(#"{"organizer":{"email":"boss@x.com","displayName":"The Boss"}}"#).organizer, "The Boss")
        XCTAssertEqual(try make(#"{"organizer":{"email":"boss@x.com"}}"#).organizer, "boss@x.com")
        XCTAssertNil(try make(#"{"organizer":{"email":"me@x.com","self":true}}"#).organizer)
    }

    func testRemindersFollowTheEventOrTheCalendarDefaults() throws {
        XCTAssertEqual(try make(#"{"reminders":{"useDefault":true}}"#).reminders, ["10 minutes before", "1 day before"])
        XCTAssertEqual(try make(#"{"reminders":{"useDefault":false,"overrides":[{"method":"popup","minutes":60},{"method":"email","minutes":60},{"method":"popup","minutes":0}]}}"#).reminders,
                       ["When it starts", "1 hour before"])
        XCTAssertEqual(try make(#"{"reminders":{"useDefault":false}}"#).reminders, [])
        XCTAssertEqual(try make("{}").reminders, [])
        XCTAssertEqual(EventDetails.reminderText(1), "1 minute before")
        XCTAssertEqual(EventDetails.reminderText(90), "90 minutes before")
        XCTAssertEqual(EventDetails.reminderText(120), "2 hours before")
        XCTAssertEqual(EventDetails.reminderText(2880), "2 days before")
        XCTAssertEqual(EventDetails.reminderText(10_080), "1 week before")
    }

    func testBusyVisibilityAndSeries() throws {
        let busy = try make(#"{"recurringEventId":"series-1"}"#)
        XCTAssertTrue(busy.busy)
        XCTAssertNil(busy.visibility)
        XCTAssertEqual(busy.recurringEventID, "series-1")
        XCTAssertFalse(try make(#"{"transparency":"transparent"}"#).busy)
        XCTAssertEqual(try make(#"{"visibility":"private"}"#).visibility, "Private")
        XCTAssertEqual(try make(#"{"visibility":"confidential"}"#).visibility, "Private")
        XCTAssertEqual(try make(#"{"visibility":"public"}"#).visibility, "Public")
        XCTAssertNil(try make(#"{"visibility":"default"}"#).visibility)
    }

    func testBlankLocationsAndDescriptionsAreDropped() throws {
        XCTAssertNil(try make(#"{"location":"  ","description":"\n"}"#).location)
        XCTAssertNil(try make(#"{"location":"  ","description":"\n"}"#).description)
        XCTAssertEqual(try make(#"{"location":"Room 4"}"#).location, "Room 4")
    }
}

final class EventTextTests: XCTestCase {
    private var cal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ from: Date, _ to: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: "c|e", calendarID: "c", title: "t", start: from, end: to, allDay: allDay, color: 0)
    }

    func testAllDayEventsNameTheirLastDayNotTheExclusiveEnd() {
        XCTAssertTrue(EventText.when(event(date(24), date(25), allDay: true), cal: cal).hasSuffix("· All day"))
        let trip = EventText.when(event(date(22), date(24), allDay: true), cal: cal)
        XCTAssertTrue(trip.contains(" – ") && trip.hasSuffix("· All day"))
        XCTAssertTrue(trip.contains("23"), trip) // ends on the 23rd, not the 24th
        XCTAssertFalse(trip.contains("24"), trip)
    }

    func testSameDayEventsShowOneDayAndATimeRange() {
        let text = EventText.when(event(date(21, 10), date(21, 11, 30)), cal: cal)
        XCTAssertTrue(text.contains(" · ") && text.contains("21"), text)
        XCTAssertFalse(text.contains(" – 2"), text) // no second date
    }

    func testAnEventEndingAtMidnightStaysOnItsDay() {
        let text = EventText.when(event(date(21, 22), date(22)), cal: cal)
        XCTAssertTrue(text.contains(" · "), text)
        XCTAssertFalse(text.contains("22 Oct") || text.contains("Oct 22"), text)
    }

    func testEventsAcrossMidnightShowBothDays() {
        let text = EventText.when(event(date(21, 22), date(22, 2)), cal: cal)
        XCTAssertTrue(text.contains(" – "), text)
        XCTAssertTrue(text.contains("21") && text.contains("22"), text)
    }
}
