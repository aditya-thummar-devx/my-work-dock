import XCTest
@testable import MyWorkDock

/// Google Calendar's REST API as the store sees it: the token endpoint, calendarList and events, with knobs per test.
private final class FakeCalendarAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var queued: [String: [(Int, String)]] = [:]
    var calendars: [(id: String, name: String, selected: Bool)] = [("cal-a", "Work", true), ("cal-b", "Team", true), ("cal-c", "Holidays", false)]
    /// Event JSON objects per calendar; a calendar without an entry has one event today.
    var events: [String: [String]] = [:]
    /// Pages per calendar (first request, then `pageToken=<next>`); wins over `events`.
    var pages: [String: [(items: [String], next: String?)]] = [:]
    /// The `events.get` answer per event id (an instance or its series).
    var eventBodies: [String: String] = [:]
    var token: (Int, String) = (200, #"{"access_token":"at-new","expires_in":3600}"#)
    var delay: TimeInterval = 0
    var networkDown = false

    /// The next events requests for `id` get these answers, in order; after that the calendar answers normally.
    func fail(_ id: String, _ answers: [(Int, String)]) { lock.withLock { queued[id] = answers } }

    var requests: [URLRequest] { lock.withLock { _requests } }
    func eventRequests(for id: String? = nil) -> [URLRequest] {
        requests.filter { $0.url?.path.hasSuffix("/events") == true && (id == nil || $0.url?.pathComponents.contains(id!) == true) }
    }
    var tokenRequests: Int { requests.filter { $0.url?.host == "oauth2.googleapis.com" }.count }
    /// `events.get` calls: the path continues past `/events`.
    var detailRequests: [URLRequest] { requests.filter { $0.url?.pathComponents.contains("events") == true && $0.url?.lastPathComponent != "events" } }

    func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    static func event(_ id: String, _ title: String, day: Int = 21, hour: Int = 10) -> String {
        let at = { (h: Int) in String(format: "2026-10-%02dT%02d:00:00+05:30", day, h) }
        return #"{"id":"\#(id)","summary":"\#(title)","start":{"dateTime":"\#(at(hour))"},"end":{"dateTime":"\#(at(hour + 1))"}}"#
    }

    var transport: HTTPTransport {
        { [self] request in
            lock.withLock { _requests.append(request) }
            if networkDown { throw URLError(.notConnectedToInternet) }
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            let url = request.url!
            func reply(_ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
                (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            if url.host == "oauth2.googleapis.com" { return reply(token.0, token.1) }
            if url.path.hasSuffix("/calendarList") {
                let items = calendars.map { ##"{"id":"\##($0.id)","summary":"\##($0.name)","backgroundColor":"#4285f4","selected":\##($0.selected),"defaultReminders":[{"method":"popup","minutes":10}]}"## }
                return reply(200, #"{"items":[\#(items.joined(separator: ","))]}"#)
            }
            let id = url.pathComponents[url.pathComponents.firstIndex(of: "calendars")! + 1]
            if let next = lock.withLock({ () -> (Int, String)? in queued[id]?.isEmpty == false ? queued[id]!.removeFirst() : nil }) { return reply(next.0, next.1) }
            if let index = url.pathComponents.firstIndex(of: "events"), index + 1 < url.pathComponents.count {
                return reply(200, eventBodies[url.pathComponents[index + 1]] ?? "{}") // events.get
            }
            if let pages = pages[id] {
                let page = query(request)["pageToken"] == nil ? pages[0] : pages[1]
                let next = page.next.map { ",\"nextPageToken\":\"\($0)\"" } ?? ""
                return reply(200, "{\"items\":[\(page.items.joined(separator: ","))]\(next)}")
            }
            let items = events[id] ?? [Self.event("e-\(id)", "Event \(id)")]
            return reply(200, #"{"items":[\#(items.joined(separator: ","))]}"#)
        }
    }
}

private final class Pauses: @unchecked Sendable {
    private let lock = NSLock()
    private var _seconds: [TimeInterval] = []
    func record(_ seconds: TimeInterval) { lock.withLock { _seconds.append(seconds) } }
    var seconds: [TimeInterval] { lock.withLock { _seconds } }
}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class CalendarDataTests: XCTestCase {
    private let config = GoogleOAuthConfig(clientID: "client-1.apps.googleusercontent.com", clientSecret: "GOCSPX-secret")
    private let suite = "mwd-calendar-tests-\(UUID().uuidString)"
    private var file: URL!
    private var api: FakeCalendarAPI!
    private var pauses: Pauses!
    private var clock: Clock!
    private var cal: Calendar!

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appending(path: "mwd-calendar-data-\(UUID().uuidString)/google-calendar.json")
        api = FakeCalendarAPI()
        pauses = Pauses()
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 1
        clock = Clock(cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10, minute: 30))!)
        save(expiresIn: 3000)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func save(expiresIn: TimeInterval) {
        let token = GoogleToken(clientID: config.clientID, refreshToken: "rt", accessToken: "at-old", expiresAt: Date(timeIntervalSinceNow: expiresIn), email: "me@devxlabs.ai")
        XCTAssertNil(SecretFile.save(try! JSONEncoder().encode(token), to: file))
    }

    private func makeStore(defaults: UserDefaults? = nil) -> CalendarStore {
        let api = api!, pauses = pauses!, clock = clock!
        let google = GoogleAuth(config: config, file: file, transport: api.transport)
        return CalendarStore(google: google, confirmer: Confirmer(), transport: api.transport, pause: { pauses.record($0) },
                             cal: cal, now: { clock.now }, defaults: defaults)
    }

    /// Lets the fetches a navigation started finish.
    private func settle(_ store: CalendarStore) async {
        try? await Task.sleep(for: .milliseconds(30))
        let end = Date().addingTimeInterval(5)
        while store.loading > 0 && Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: What is fetched

    func testRefreshLoadsTheCalendarListThenOnlyTheShownCalendarsForTheVisibleWeek() async throws {
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.calendars.map(\.id), ["cal-a", "cal-b", "cal-c"])
        XCTAssertEqual(Set(api.eventRequests().map { $0.url!.pathComponents[4] }), ["cal-a", "cal-b"]) // cal-c is not ticked at Google
        let query = api.query(try XCTUnwrap(api.eventRequests(for: "cal-a").first))
        XCTAssertEqual(query["timeMin"], "2026-10-17T18:30:00Z") // Sun 18 Oct 00:00 in Kolkata
        XCTAssertEqual(query["timeMax"], "2026-10-24T18:30:00Z") // Sun 25 Oct 00:00
        XCTAssertEqual(query["singleEvents"], "true")
        XCTAssertEqual(query["orderBy"], "startTime")
        XCTAssertEqual(query["timeZone"], "Asia/Kolkata")
        XCTAssertEqual(query["maxResults"], "2500")
        XCTAssertFalse(try XCTUnwrap(api.eventRequests().first?.url?.absoluteString).contains("workingLocation"))
        XCTAssertEqual(store.visibleEvents.map(\.title).sorted(), ["Event cal-a", "Event cal-b"])
        XCTAssertEqual(api.eventRequests(for: "cal-a").first?.value(forHTTPHeaderField: "Authorization"), "Bearer at-old")
    }

    func testASecondRefreshInsideTheTTLAsksNothingAndAfterItFetchesAgain() async throws {
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(api.eventRequests().count, 2)
        await store.refresh()
        XCTAssertEqual(api.eventRequests().count, 2)
        clock.now = clock.now.addingTimeInterval(61)
        await store.refresh()
        XCTAssertEqual(api.eventRequests().count, 4)
        await store.refresh(force: true)
        XCTAssertEqual(api.eventRequests().count, 6) // ↻ ignores the cache
    }

    func testMonthCoversWeekAndDayAndNavigationFetchesOnlyWhatIsNew() async throws {
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(api.eventRequests().count, 2)
        store.setMode(.month)
        await settle(store)
        XCTAssertEqual(api.eventRequests().count, 4) // the month grid reaches beyond the week
        store.setMode(.week)
        await settle(store)
        store.setMode(.day)
        await settle(store)
        store.go(.next)
        await settle(store)
        XCTAssertEqual(api.eventRequests().count, 4) // week and day sit inside the month that is already fresh
        store.setMode(.month)
        await settle(store)
        store.go(.next) // November
        await settle(store)
        XCTAssertEqual(api.eventRequests().count, 6)
    }

    func testTheSameEventFromTwoRangesShowsOnce() async throws {
        api.events["cal-a"] = [FakeCalendarAPI.event("same", "Same", day: 21)]
        let store = makeStore()
        await store.refresh() // the week
        store.setMode(.month)
        await settle(store) // the month: the same event arrives again
        XCTAssertEqual(store.visibleEvents.filter { $0.title == "Same" }.count, 1)
    }

    func testPagesAreJoined() async throws {
        api.pages["cal-a"] = [(items: [FakeCalendarAPI.event("one", "First")], next: "p2"), (items: [FakeCalendarAPI.event("two", "Second", day: 22)], next: nil)]
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(api.eventRequests(for: "cal-a").count, 2)
        XCTAssertEqual(api.query(api.eventRequests(for: "cal-a")[1])["pageToken"], "p2")
        XCTAssertEqual(Set(store.visibleEvents.map(\.title)), ["First", "Second", "Event cal-b"])
    }

    // MARK: Event sheet

    private func until(_ what: String, timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }

    private func firstEvent(_ store: CalendarStore, of calendarID: String = "cal-a") throws -> CalendarEvent {
        try XCTUnwrap(store.visibleEvents.first { $0.calendarID == calendarID })
    }

    func testSelectingAnEventOpensItAtOnceThenFetchesDetailsAndTheSeriesRule() async throws {
        api.eventBodies["e-cal-a"] = #"{"hangoutLink":"https://meet.google.com/abc-defg-hij","location":"Room 4","recurringEventId":"series-1","reminders":{"useDefault":true}}"#
        api.eventBodies["series-1"] = #"{"recurrence":["RRULE:FREQ=WEEKLY;BYDAY=WE"]}"#
        let store = makeStore()
        await store.refresh()
        let event = try firstEvent(store)
        store.select(event)
        XCTAssertEqual(store.selected?.id, event.id)
        XCTAssertEqual(store.detail, .loading) // the sheet is up with the title and time; the rest follows
        await until("details and rule") { if case .loaded(let d) = store.detail { return d.recurrence != nil } else { return false } }
        guard case .loaded(let details) = store.detail else { return XCTFail("\(store.detail)") }
        XCTAssertEqual(details.location, "Room 4")
        XCTAssertEqual(details.meetURL, URL(string: "https://meet.google.com/abc-defg-hij"))
        XCTAssertEqual(details.reminders, ["10 minutes before"]) // the calendar's default
        XCTAssertEqual(details.recurrence, "Weekly on Wednesday")
        XCTAssertEqual(api.detailRequests.count, 2)
        XCTAssertTrue(api.detailRequests[0].url!.absoluteString.contains("conferenceData"))
        XCTAssertEqual(api.query(api.detailRequests[1])["fields"], "recurrence")
    }

    func testAnEventWithoutASeriesNeedsOnlyOneRead() async throws {
        api.eventBodies["e-cal-a"] = #"{"location":"Room 4"}"#
        let store = makeStore()
        await store.refresh()
        store.select(try firstEvent(store))
        await until("details") { if case .loaded = store.detail { return true } else { return false } }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(api.detailRequests.count, 1)
    }

    func testSwitchingEventsDropsTheOldAnswer() async throws {
        api.eventBodies["e-cal-a"] = #"{"location":"Room A"}"#
        api.eventBodies["e-cal-b"] = #"{"location":"Room B"}"#
        let store = makeStore()
        await store.refresh()
        api.delay = 0.2
        store.select(try firstEvent(store, of: "cal-a"))
        try await Task.sleep(for: .milliseconds(50))
        store.select(try firstEvent(store, of: "cal-b"))
        await until("the second event's details") { if case .loaded(let d) = store.detail { return d.location == "Room B" } else { return false } }
        try await Task.sleep(for: .milliseconds(300)) // the first answer would have landed by now
        XCTAssertEqual(store.selected?.calendarID, "cal-b")
        guard case .loaded(let details) = store.detail else { return XCTFail("\(store.detail)") }
        XCTAssertEqual(details.location, "Room B")
    }

    func testADetailFailureSaysWhyAndRetryTriesAgain() async throws {
        let store = makeStore()
        await store.refresh()
        api.fail("cal-a", [(404, #"{"error":{"message":"Not Found"}}"#)])
        store.select(try firstEvent(store))
        await until("the failure") { store.detail == .failed("Not Found") }
        store.retryDetail()
        await until("the retry") { if case .loaded = store.detail { return true } else { return false } }
    }

    func testTheSheetClosesWhenTheTabOrTheMenuGoes() async throws {
        let store = makeStore()
        await store.refresh()
        store.select(try firstEvent(store))
        XCTAssertNotNil(store.selected)
        store.closeMenus() // what leaving the tab, collapsing and leaving the panel call
        XCTAssertNil(store.selected)
        store.select(try firstEvent(store))
        store.stop() // the menu switched off
        XCTAssertNil(store.selected)
    }

    func testLinksLeaveThroughTheBrowserAfterThePanelCloses() {
        let store = makeStore()
        var log: [String] = []
        store.willOpenBrowser = { log.append("close panel") }
        store.openURL = { log.append($0.absoluteString) }
        store.open(URL(string: "https://meet.google.com/x")!)
        XCTAssertEqual(log, ["close panel", "https://meet.google.com/x"])
    }

    func testTheSampleStoreServesCannedDetails() throws {
        let store = CalendarStore.sample(.signedIn(email: "me@x.com"))
        let call = try XCTUnwrap(store.visibleEvents.first { $0.title.hasPrefix("Client call") })
        store.select(call)
        guard case .loaded(let details) = store.detail else { return XCTFail("\(store.detail)") }
        XCTAssertNotNil(details.meetURL)
        XCTAssertEqual(details.guests.count, 6)
        XCTAssertEqual(details.recurrence, "Weekly on Wednesday")
    }

    // MARK: Calendars menu

    func testHiddenCalendarsAreNotFetchedAndTheChoicePersists() async throws {
        let defaults = UserDefaults(suiteName: suite)!
        let store = makeStore(defaults: defaults)
        await store.refresh()
        store.toggle("cal-b")
        await settle(store)
        XCTAssertEqual(store.shownCalendars.map(\.id), ["cal-a"])
        XCTAssertFalse(store.visibleEvents.contains { $0.calendarID == "cal-b" }) // its events leave the grid at once
        store.toggle("cal-c") // Google had it unticked; the user ticks it
        await settle(store)
        XCTAssertEqual(api.eventRequests(for: "cal-c").count, 1)
        let relaunched = makeStore(defaults: defaults)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.shownCalendars.map(\.id), ["cal-a", "cal-c"])
    }

    // MARK: Navigation

    func testGoShiftsByTheViewAndTheViewIsRemembered() async throws {
        let defaults = UserDefaults(suiteName: suite)!
        let store = makeStore(defaults: defaults)
        XCTAssertEqual(store.mode, .week) // the default
        store.go(.next)
        XCTAssertEqual(store.anchor, cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 10, minute: 30)))
        store.go(.today)
        XCTAssertEqual(store.anchor, clock.now)
        store.cycleMode()
        XCTAssertEqual(store.mode, .day)
        store.cycleMode()
        XCTAssertEqual(store.mode, .month)
        XCTAssertEqual(makeStore(defaults: defaults).mode, .month)
        store.openDay(cal.date(from: DateComponents(year: 2026, month: 10, day: 30))!)
        XCTAssertEqual(store.mode, .day)
        XCTAssertEqual(store.visibleDays, [cal.date(from: DateComponents(year: 2026, month: 10, day: 30))!])
        await settle(store)
    }

    // MARK: Failures

    func test401RefreshesTheTokenOnceThenSucceeds() async throws {
        api.fail("cal-a", [(401, #"{"error":{"message":"Invalid Credentials"}}"#)])
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(api.tokenRequests, 1)
        let sent = api.eventRequests(for: "cal-a")
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[1].value(forHTTPHeaderField: "Authorization"), "Bearer at-new")
        XCTAssertTrue(store.visibleEvents.contains { $0.calendarID == "cal-a" })
        XCTAssertTrue(store.failures.isEmpty)
    }

    func testRateLimitBacksOffThreeTimesThenReportsIt() async throws {
        let limited = (403, #"{"error":{"code":403,"message":"Rate Limit Exceeded","errors":[{"reason":"rateLimitExceeded"}]}}"#)
        api.fail("cal-a", Array(repeating: limited, count: 10))
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(api.eventRequests(for: "cal-a").count, 4) // the try and three retries
        XCTAssertEqual(pauses.seconds.count, 3)
        XCTAssertTrue((1.0..<1.5).contains(pauses.seconds[0]) && (2.0..<2.5).contains(pauses.seconds[1]) && (4.0..<4.5).contains(pauses.seconds[2]))
        XCTAssertEqual(store.failures["cal-a"], "Rate Limit Exceeded")
        XCTAssertTrue(store.visibleEvents.contains { $0.calendarID == "cal-b" }) // the other calendar still loaded
        XCTAssertEqual(store.footer, StatusMessage(text: "Rate Limit Exceeded", isError: true))
    }

    func testAForbiddenThatIsNotARateLimitFailsAtOnce() async throws {
        api.fail("cal-a", [(403, #"{"error":{"message":"Forbidden"}}"#)])
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(api.eventRequests(for: "cal-a").count, 1)
        XCTAssertTrue(pauses.seconds.isEmpty)
        XCTAssertEqual(store.failures["cal-a"], "Forbidden")
    }

    func testOneFailingCalendarDoesNotHideTheOthers() async throws {
        api.fail("cal-b", [(404, #"{"error":{"message":"Not Found"}}"#)])
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.failures, ["cal-b": "Not Found"])
        XCTAssertEqual(store.visibleEvents.map(\.calendarID), ["cal-a"])
        XCTAssertEqual(store.footer, StatusMessage(text: "Not Found", isError: true))
        api.fail("cal-a", [(404, #"{"error":{"message":"Gone"}}"#)]) // cal-b now answers fine again, so it recovers
        await store.refresh(force: true)
        XCTAssertEqual(store.failures, ["cal-a": "Gone"])
        api.fail("cal-a", [(404, #"{"error":{"message":"Gone"}}"#)])
        api.fail("cal-b", [(404, #"{"error":{"message":"Not Found"}}"#)])
        await store.refresh(force: true)
        XCTAssertEqual(store.footer, StatusMessage(text: "2 calendars failed to load", isError: true))
    }

    func testGoingOfflineKeepsWhatWasLoaded() async throws {
        let store = makeStore()
        await store.refresh()
        api.networkDown = true
        await store.refresh(force: true)
        XCTAssertTrue(store.offline)
        XCTAssertEqual(store.visibleEvents.count, 2)
        XCTAssertEqual(store.footer, StatusMessage(text: "Offline · showing what was loaded", isError: true))
        if case .signedIn = store.auth {} else { XCTFail("offline is not a sign-out") }
        api.networkDown = false
        await store.refresh(force: true)
        XCTAssertFalse(store.offline)
        XCTAssertTrue(store.footer.text.hasPrefix("2 events · updated"))
    }

    func testADeadRefreshTokenDuringAFetchBringsBackSignIn() async throws {
        save(expiresIn: -10)
        api.token = (400, #"{"error":"invalid_grant"}"#)
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.auth, .signedOut(.expired))
        XCTAssertTrue(store.calendars.isEmpty)
        XCTAssertTrue(store.chunks.isEmpty)
        XCTAssertNil(SecretFile.load(file))
    }

    func testStoppingTheMenuDropsFetchesStillInFlight() async throws {
        api.delay = 0.3
        let store = makeStore()
        let running = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(100))
        store.stop() // the menu was switched off mid-fetch
        await running.value
        XCTAssertTrue(store.calendars.isEmpty)
        XCTAssertTrue(store.chunks.isEmpty)
        XCTAssertEqual(store.loading, 0)
    }

    func testSignOutDiscardsWhatIsStillComing() async throws {
        let store = makeStore()
        await store.refresh()
        api.delay = 0.3
        let running = Task { await store.refresh(force: true) }
        try await Task.sleep(for: .milliseconds(100))
        store.askSignOut()
        store.confirmer.confirm()
        await running.value
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(store.auth, .signedOut(nil))
        XCTAssertTrue(store.chunks.isEmpty) // the fetch that landed after sign-out was dropped
        XCTAssertTrue(store.calendars.isEmpty)
    }
}
