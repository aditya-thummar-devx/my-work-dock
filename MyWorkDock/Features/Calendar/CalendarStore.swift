import AppKit
import Foundation
import Observation

/// My Calendar: the Google sign-in state machine, and the events behind the Month / Week / Day views.
/// signedOut → signingIn (browser open, listener waiting) → signedIn. A refresh token Google no longer accepts brings back
/// signedOut(.expired). Events are fetched for the visible range only, per calendar, kept in memory for 60 s (like claudex),
/// and fetched again on panel open, navigation and ↻. `google == nil` (snapshots, tests, a build without an OAuth client)
/// never touches the network.
@MainActor @Observable
final class CalendarStore {
    enum SignedOutReason: Equatable {
        case expired
        case failed(String)
        case notConfigured
    }

    enum Auth: Equatable {
        case signedOut(SignedOutReason?)
        case signingIn
        case signedIn(email: String)
    }

    enum Step { case previous, next, today }

    /// The sheet of the clicked event: the title and time are known at once, the rest is fetched.
    enum DetailState: Equatable {
        case loading
        case loaded(EventDetails)
        case failed(String)
    }

    /// What one fetch brought back: the events of `calendarID` that touch `from..<to`.
    struct Chunk: Equatable {
        var calendarID: String
        var from: Date
        var to: Date
        var events: [CalendarEvent]
        var fetchedAt: Date
    }

    // Sign-in
    private(set) var auth: Auth
    let confirmer: Confirmer
    @ObservationIgnored let live: Bool
    @ObservationIgnored private let google: GoogleAuth?
    /// Opens the Google consent page. Injected by tests, which play the browser.
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Right before the browser opens (the open panel floats above it) and after a successful sign-in.
    @ObservationIgnored var willOpenBrowser: (() -> Void)?
    @ObservationIgnored var onSignedIn: (() -> Void)?
    @ObservationIgnored private var flow: Task<Void, Never>?
    /// Identifies the running sign-in: a cancelled one finishing late must not overwrite the next one's state.
    @ObservationIgnored private var flowID = 0

    // View
    private(set) var mode: CalendarMode
    /// Any moment inside what is shown: the day, the week or the month.
    private(set) var anchor: Date
    var calendarsMenuOpen = false
    /// An instant the hour grid scrolls to (an event opened from the peek), until the next navigation. nil: its usual spot.
    private(set) var focus: Date?
    private(set) var selected: CalendarEvent?
    private(set) var detail = DetailState.loading
    /// "Copied" on the Meet link button for a moment.
    private(set) var copied = false
    /// "+6 more" was pressed: the sheet lists every guest instead of the first few.
    private(set) var guestsExpanded = false

    // Data
    private(set) var calendars: [CalendarInfo] = []
    private(set) var chunks: [Chunk] = []
    /// The user's show/hide choices; a calendar never touched here follows Google's own `selected` flag.
    private(set) var shownOverrides: [String: Bool]
    private(set) var loading = 0
    /// Calendars whose last fetch failed, with why.
    private(set) var failures: [String: String] = [:]
    private(set) var offline = false
    private(set) var fetchedAt: Date?

    @ObservationIgnored var cal: Calendar
    @ObservationIgnored var now: () -> Date
    @ObservationIgnored private let client: GoogleCalendarClient?
    @ObservationIgnored private let defaults: UserDefaults?
    /// `calendar|from|to` of the fetches running now.
    @ObservationIgnored private var inFlight: Set<String> = []
    /// Bumped by sign-out, expiry and "menu off": a fetch that finishes afterwards is dropped.
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var detailTask: Task<Void, Never>?

    static let signInTimeout: TimeInterval = 300
    static let ttl: TimeInterval = 60

    init(google: GoogleAuth?, confirmer: Confirmer, transport: @escaping HTTPTransport = HTTP.live,
         pause: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
         cal: Calendar = .current, now: @escaping () -> Date = { Date() }, defaults: UserDefaults? = nil, live: Bool = true) {
        self.google = google
        self.confirmer = confirmer
        self.live = live
        self.cal = cal
        self.now = now
        self.defaults = defaults
        client = google.map { GoogleCalendarClient(auth: $0, transport: transport, pause: pause) }
        mode = defaults?.string(forKey: "calendarView").flatMap(CalendarMode.init(rawValue:)) ?? .week
        shownOverrides = defaults?.dictionary(forKey: "calendarShown") as? [String: Bool] ?? [:]
        anchor = now()
        if let google {
            auth = google.initialEmail.map { .signedIn(email: $0) } ?? .signedOut(nil)
        } else {
            auth = .signedOut(.notConfigured)
        }
    }

    static func live(confirmer: Confirmer) -> CalendarStore {
        let google = GoogleOAuthConfig.fromBundle().map { GoogleAuth(config: $0, file: JSONFile.url("google-calendar.json")) }
        let store = CalendarStore(google: google, confirmer: confirmer, cal: .autoupdatingCurrent, defaults: .standard)
        // Events are real instants but all-day events are local midnights: a new time zone invalidates what was fetched.
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.timeZoneChanged() }
        }
        return store
    }

    /// The designs' sample week (see `CalendarSample`): signed in, four calendars, no network.
    static func sample(_ auth: Auth = .signedOut(nil), mode: CalendarMode = .week) -> CalendarStore {
        let cal = CalendarSample.calendar
        let store = CalendarStore(google: nil, confirmer: Confirmer(), cal: cal, now: { CalendarSample.now }, live: false)
        store.auth = auth
        store.mode = mode
        store.calendars = CalendarSample.calendars
        store.chunks = CalendarSample.chunks(cal: cal)
        store.fetchedAt = CalendarSample.now
        return store
    }

    #if DEBUG
    /// Snapshots draw each state.
    func preview(_ auth: Auth, mode: CalendarMode? = nil, menuOpen: Bool = false, selecting title: String? = nil, allGuests: Bool = false,
                 scrolledTo scrollTitle: String? = nil) {
        self.auth = auth
        if let mode { self.mode = mode }
        calendarsMenuOpen = menuOpen
        if let title, let event = visibleEvents.first(where: { $0.title == title }) { select(event) }
        if allGuests { showAllGuests() }
        if let scrollTitle, let event = visibleEvents.first(where: { $0.title == scrollTitle }) { focus = event.start }
    }
    #endif

    // MARK: Derived

    var isSigningIn: Bool { auth == .signingIn }
    var visibleDays: [Date] { CalendarLayout.visibleDays(mode, around: anchor, cal: cal) }

    func isShown(_ calendar: CalendarInfo) -> Bool { shownOverrides[calendar.id] ?? calendar.selected }
    var shownCalendars: [CalendarInfo] { calendars.filter(isShown) }

    /// Events of every shown calendar that touch the visible days, each once (an event near a range edge arrives with two fetches).
    var visibleEvents: [CalendarEvent] {
        let (from, to) = CalendarLayout.range(of: visibleDays, cal: cal)
        let shown = Set(shownCalendars.map(\.id))
        var seen = Set<String>()
        return chunks
            .filter { shown.contains($0.calendarID) && $0.from < to && $0.to > from }
            .flatMap(\.events)
            .filter { $0.start < to && $0.end > from && seen.insert($0.id).inserted }
    }

    /// What is left of today for the peek: timed events that have not ended and were not declined, on the shown calendars, soonest
    /// first. nil until a fetch that covers today has landed (and while signed out). Reads what is cached, however old: the hover
    /// that shows it also starts `refreshToday()`.
    func upcomingToday() -> [CalendarEvent]? {
        guard case .signedIn = auth else { return nil }
        let current = now()
        let day = cal.startOfDay(for: current)
        guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
        let shown = Set(shownCalendars.map(\.id))
        // Per calendar only the freshest fetch that covers today: an older copy must not bring back what a newer one dropped.
        var freshest: [String: Chunk] = [:]
        for chunk in chunks where shown.contains(chunk.calendarID) && chunk.from <= day && chunk.to >= next {
            if let known = freshest[chunk.calendarID], known.fetchedAt >= chunk.fetchedAt { continue }
            freshest[chunk.calendarID] = chunk
        }
        guard !freshest.isEmpty else { return nil }
        var seen = Set<String>()
        return freshest.values.flatMap(\.events)
            .filter { !$0.allDay && !$0.declined && $0.end > current && $0.start < next && seen.insert($0.id).inserted }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
    }

    var title: String {
        let days = visibleDays
        switch mode {
        case .month: return anchor.formatted(.dateTime.month(.wide).year())
        case .week: return (days[0]..<days[days.count - 1]).formatted(.interval.day().month(.abbreviated).year())
        case .day: return anchor.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        }
    }

    var footer: StatusMessage {
        switch auth {
        case .signedOut(nil): StatusMessage(text: "Sign in to see your calendar")
        case .signedOut(.expired): StatusMessage(text: "Session expired · sign in again")
        case .signedOut(.failed(let why)): StatusMessage(text: why, isError: true)
        case .signedOut(.notConfigured): StatusMessage(text: "Google sign-in is not configured")
        case .signingIn: StatusMessage(text: "Waiting for Google…")
        case .signedIn(let email): signedInFooter(email)
        }
    }

    private func signedInFooter(_ email: String) -> StatusMessage {
        if failures.count > 1 { return StatusMessage(text: "\(failures.count) calendars failed to load", isError: true) }
        if let why = failures.values.first { return StatusMessage(text: why, isError: true) }
        if offline { return StatusMessage(text: "Offline · showing what was loaded", isError: true) }
        if loading > 0 { return StatusMessage(text: "Loading…") }
        guard let at = fetchedAt else { return StatusMessage(text: email) }
        let count = visibleEvents.count
        return StatusMessage(text: "\(count) event\(count == 1 ? "" : "s") · updated \(at.formatted(date: .omitted, time: .shortened))")
    }

    var accountEmail: String? {
        if case .signedIn(let email) = auth { email } else { nil }
    }

    // MARK: Sign in / out

    func signIn() {
        guard let google, !isSigningIn else { return }
        auth = .signingIn
        flowID += 1
        let id = flowID
        flow = Task { await runSignIn(google, id: id) }
    }

    /// Cancel on the waiting screen.
    func cancelSignIn() {
        flowID += 1
        flow?.cancel()
        flow = nil
        if isSigningIn { auth = .signedOut(nil) }
    }

    /// The menu was switched off: no sign-in left running, no fetch left to land, nothing kept in memory.
    func stop() {
        cancelSignIn()
        epoch += 1
        clearData()
    }

    func askSignOut() {
        guard case .signedIn(let email) = auth, let google else { return }
        calendarsMenuOpen = false
        confirmer.ask(ConfirmRequest(title: "Sign out of Google?", command: "Revoke MyWorkDock's access to \(email)",
                                     note: "Your calendar leaves this panel until you sign in again.", confirmTitle: "Sign out") { [weak self] in
            await google.signOut()
            self?.epoch += 1
            self?.clearData()
            self?.auth = .signedOut(nil)
        })
    }

    /// Proves the saved session still works. A refresh token that Google no longer accepts puts the sign-in screen back;
    /// any other failure (offline, Google down) leaves the session alone.
    func verifySession() async {
        guard let google, case .signedIn = auth else { return }
        do { _ = try await google.accessToken() } catch GoogleAuthError.invalidGrant { expire() } catch {}
    }

    private func expire() {
        epoch += 1
        clearData()
        auth = .signedOut(.expired)
    }

    private func clearData() {
        closeDetail()
        calendars = []
        chunks = []
        failures = [:]
        inFlight = []
        loading = 0
        offline = false
        fetchedAt = nil
    }

    private func runSignIn(_ google: GoogleAuth, id: Int) async {
        let server = LoopbackServer(state: PKCE.state())
        defer { server.stop() }
        do {
            let port = try await server.start()
            let verifier = PKCE.verifier()
            let redirect = "http://127.0.0.1:\(port)/"
            let url = google.authorizationURL(redirect: redirect, state: server.state, challenge: PKCE.challenge(for: verifier))
            willOpenBrowser?()
            openURL(url)
            let code = try await server.callback(timeout: Self.signInTimeout)
            let email = try await google.signIn(code: code, verifier: verifier, redirect: redirect)
            guard id == flowID else { return }
            auth = .signedIn(email: email)
            flow = nil
            onSignedIn?()
            await refresh()
        } catch is CancellationError {
            guard id == flowID else { return }
            auth = .signedOut(nil)
            flow = nil
        } catch {
            guard id == flowID else { return }
            auth = .signedOut(.failed(Self.message(for: error)))
            flow = nil
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LoopbackServer.Failure.denied: "Sign-in was cancelled."
        case LoopbackServer.Failure.timeout: "Sign-in timed out. Try again."
        case LoopbackServer.Failure.couldNotStart: "Could not start the local sign-in listener."
        case GoogleAuthError.noRefreshToken: "Google sent no refresh token. Remove MyWorkDock at myaccount.google.com/permissions, then sign in again."
        case GoogleAuthError.invalidClient: "Google rejected this build's OAuth client. The build is misconfigured."
        case GoogleAuthError.network: "Could not reach Google. Check your connection."
        case GoogleAuthError.server(let why): why
        default: error.localizedDescription
        }
    }

    // MARK: Navigation

    func go(_ step: Step) {
        switch step {
        case .today: anchor = now()
        case .previous: anchor = CalendarLayout.shifted(anchor, mode, by: -1, cal: cal)
        case .next: anchor = CalendarLayout.shifted(anchor, mode, by: 1, cal: cal)
        }
        focus = nil
        reload()
    }

    func setMode(_ new: CalendarMode) {
        mode = new
        focus = nil
        defaults?.set(new.rawValue, forKey: "calendarView")
        reload()
    }

    /// An event clicked in the peek: the view moves to `day`, the hour grid scrolls to where the event starts (or to midnight when
    /// it began earlier) and its sheet opens, as if it had been clicked in the grid. The Month / Week / Day choice stays; Month has
    /// no hours, so there it only opens the sheet.
    func reveal(_ event: CalendarEvent, on day: Date) {
        anchor = day
        focus = max(event.start, cal.startOfDay(for: day))
        reload()
        select(event)
    }

    /// Shift+Tab: Month → Week → Day → Month.
    func cycleMode() {
        let all = CalendarMode.allCases
        setMode(all[((all.firstIndex(of: mode) ?? 0) + 1) % all.count])
    }

    /// A day in the month grid was clicked.
    func openDay(_ day: Date) {
        anchor = day
        setMode(.day)
    }

    func toggleCalendarsMenu() { calendarsMenuOpen.toggle() }

    /// Leaving the tab, collapsing or leaving the panel: the menu and the event sheet go.
    func closeMenus() {
        calendarsMenuOpen = false
        focus = nil
        closeDetail()
    }

    func toggle(_ calendarID: String) {
        guard let calendar = calendars.first(where: { $0.id == calendarID }) else { return }
        shownOverrides[calendarID] = !isShown(calendar)
        defaults?.set(shownOverrides, forKey: "calendarShown")
        reload()
    }

    private func timeZoneChanged() {
        chunks = []
        reload(force: true)
    }

    // MARK: Event sheet

    /// An event was clicked: the sheet opens on what the grid knows, and the rest (guests, Meet link, description, the series'
    /// rule) is fetched.
    func select(_ event: CalendarEvent) {
        calendarsMenuOpen = false
        selected = event
        detail = .loading
        copied = false
        guestsExpanded = false
        detailTask?.cancel()
        detailTask = nil
        guard let client else {
            detail = .loaded(live ? EventDetails() : CalendarSample.details(for: event))
            return
        }
        guard !event.eventID.isEmpty, let calendar = calendars.first(where: { $0.id == event.calendarID }) else {
            detail = .loaded(EventDetails())
            return
        }
        let started = epoch
        detailTask = Task { await loadDetail(of: event, in: calendar, client, started) }
    }

    func closeDetail() {
        detailTask?.cancel()
        detailTask = nil
        selected = nil
        detail = .loading
        guestsExpanded = false
    }

    func showAllGuests() { guestsExpanded = true }

    func retryDetail() {
        if let selected { select(selected) }
    }

    /// Links leave the panel: it floats above the browser, so it closes first.
    func open(_ url: URL) {
        willOpenBrowser?()
        openURL(url)
    }

    func copyMeetLink(_ url: URL) {
        Clipboard.copy(url.absoluteString)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func loadDetail(of event: CalendarEvent, in calendar: CalendarInfo, _ client: GoogleCalendarClient, _ started: Int) async {
        do {
            var details = try await client.details(of: event, in: calendar)
            guard started == epoch, selected?.id == event.id else { return }
            detail = .loaded(details)
            // An instance only knows its series' id: the rule ("Weekly on Wednesday") is one more read, shown when it arrives.
            if let series = details.recurringEventID, let rule = try? await client.recurrence(ofSeries: series, in: calendar) {
                guard started == epoch, selected?.id == event.id else { return }
                details.recurrence = Recurrence.describe(rule, start: event.start, cal: cal)
                detail = .loaded(details)
            }
        } catch is CancellationError {
            return
        } catch GoogleAuthError.invalidGrant {
            if started == epoch { expire() }
        } catch {
            guard started == epoch, selected?.id == event.id else { return }
            switch error {
            case CalendarAPIError.network: detail = .failed("Could not reach Google.")
            case CalendarAPIError.http(_, let why): detail = .failed(why)
            default: detail = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Fetching

    /// The calendar screen appeared (panel opened or tab switched).
    func opened() async {
        await verifySession()
        await refresh()
    }

    private func reload(force: Bool = false) { Task { await refresh(force: force) } }

    private static func key(_ id: String, _ from: Date, _ to: Date) -> String { "\(id)|\(from.timeIntervalSince1970)|\(to.timeIntervalSince1970)" }

    private func isFresh(_ id: String, _ from: Date, _ to: Date) -> Bool {
        chunks.contains { $0.calendarID == id && $0.from <= from && $0.to >= to && now().timeIntervalSince($0.fetchedAt) < Self.ttl }
    }

    /// Loads what the visible range still lacks, one request per shown calendar. A fresh fetch that already covers the range
    /// (Month → Week → Day) is reused; `force` (↻) asks again.
    func refresh(force: Bool = false) async { await refresh(range: nil, force: force) }

    /// The peek was hovered: today's events, whatever range the tab shows. Reuses any fetch under a minute old.
    func refreshToday() async {
        await refresh(range: CalendarLayout.range(of: [cal.startOfDay(for: now())], cal: cal), force: false)
    }

    /// `range` nil is what the tab shows; it is read after the calendar list arrives, so a late answer never fetches a stale range.
    private func refresh(range: (from: Date, to: Date)?, force: Bool) async {
        guard let client, case .signedIn = auth else { return }
        let started = epoch
        if calendars.isEmpty {
            do {
                let list = try await client.calendars()
                guard started == epoch else { return }
                calendars = list
            } catch is CancellationError {
                return
            } catch GoogleAuthError.invalidGrant {
                if started == epoch { expire() }
                return
            } catch let error as CalendarAPIError {
                guard started == epoch else { return }
                if case .network = error { offline = true } else if case .http(_, let why) = error { failures["calendarList"] = why }
                return
            } catch {
                return
            }
            failures["calendarList"] = nil
        }
        let (from, to) = range ?? CalendarLayout.range(of: visibleDays, cal: cal)
        let todo = shownCalendars.filter { !inFlight.contains(Self.key($0.id, from, to)) && (force || !isFresh($0.id, from, to)) }
        guard !todo.isEmpty else { return }
        for calendar in todo { inFlight.insert(Self.key(calendar.id, from, to)) }
        loading += todo.count
        await withTaskGroup(of: Void.self) { group in
            for calendar in todo { group.addTask { await self.fetch(calendar, from, to, client, started) } }
        }
    }

    private func fetch(_ calendar: CalendarInfo, _ from: Date, _ to: Date, _ client: GoogleCalendarClient, _ started: Int) async {
        defer {
            inFlight.remove(Self.key(calendar.id, from, to))
            loading = max(0, loading - 1)
        }
        do {
            let events = try await client.events(in: calendar, from: from, to: to, cal: cal)
            guard started == epoch else { return }
            store(Chunk(calendarID: calendar.id, from: from, to: to, events: events, fetchedAt: now()))
            failures[calendar.id] = nil
            offline = false
            fetchedAt = now()
        } catch is CancellationError {
            return
        } catch GoogleAuthError.invalidGrant {
            if started == epoch { expire() }
        } catch let error as CalendarAPIError {
            guard started == epoch else { return }
            switch error {
            case .network: offline = true
            case .http(_, let why): failures[calendar.id] = why
            }
        } catch {
            guard started == epoch else { return }
            failures[calendar.id] = error.localizedDescription
        }
    }

    private func store(_ chunk: Chunk) {
        chunks.removeAll { $0.calendarID == chunk.calendarID && $0.from == chunk.from && $0.to == chunk.to }
        chunks.append(chunk)
        if chunks.count > 60 { chunks = Array(chunks.sorted { $0.fetchedAt > $1.fetchedAt }.prefix(40)) }
    }
}
