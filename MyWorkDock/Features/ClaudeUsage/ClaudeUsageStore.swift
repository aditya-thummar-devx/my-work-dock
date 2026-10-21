import Foundation
import Observation

/// What the Tokens & cost tab shows, from Claude Code's own transcripts on this Mac. It never calls claudex: the tab works without it.
/// `live == false` (snapshots, tests) never reads a file. The engine, and with it the saved totals, is only built once something asks.
@MainActor @Observable
final class ClaudeUsageStore {
    private(set) var snapshot: UsageSnapshot?
    private(set) var loading = false
    private(set) var fetchedAt: Date?
    /// Why the totals could not be saved; they still show for this run.
    private(set) var saveError: String?

    @ObservationIgnored let live: Bool
    @ObservationIgnored var now: () -> Date = { Date() }
    /// Follows the system: a time-zone change moves "today" and the month edges without a relaunch.
    @ObservationIgnored var calendar: Calendar = .autoupdatingCurrent
    @ObservationIgnored private let makeEngine: () -> UsageEngine
    @ObservationIgnored private var engine: UsageEngine?
    @ObservationIgnored private let defaults: UserDefaults?

    /// Set once the tab has been opened: from then on the app also looks at launch, so no day is lost to Claude Code's cleanup as long
    /// as the app starts (or the tab opens) at least once every 30 days; a longer gap shows as a partial month. Until then nothing is read,
    /// on a Mac that only ever sees the claudex tabs.
    static let activeKey = "claudeUsageActive"
    static let footer = "From Claude Code's transcripts on this Mac · cost at API list prices"

    init(makeEngine: @escaping () -> UsageEngine = { UsageEngine() }, defaults: UserDefaults? = .standard) {
        self.makeEngine = makeEngine
        self.defaults = defaults
        live = true
    }

    /// The designs' sample content.
    init(sample: Bool) {
        makeEngine = { UsageEngine(stateURL: nil) }
        defaults = nil
        live = false
        let fixed = SampleData.now
        now = { fixed }
        calendar = SampleData.calendar
        snapshot = SampleData.usageSnapshot
        fetchedAt = fixed
    }

    var cards: [UsageCardModel] { snapshot.map { UsageCards.make($0, calendar: calendar) } ?? [] }

    var freshLabel: String {
        guard let fetchedAt else { return "not loaded" }
        let age = Int(now().timeIntervalSince(fetchedAt))
        return age < 5 ? "just now" : age < 60 ? "\(age)s ago" : "\(age / 60)m ago"
    }

    private func theEngine() -> UsageEngine {
        if let engine { return engine }
        let made = makeEngine()
        engine = made
        return made
    }

    /// One look at the transcripts; a second call while one runs does nothing.
    func refresh() async {
        guard live, !loading else { return }
        loading = true
        defer { loading = false }
        let engine = theEngine()
        snapshot = await engine.refresh(now: now(), calendar: calendar)
        saveError = await engine.saveError
        fetchedAt = now()
    }

    /// Refresh button.
    func refreshNow() {
        guard live else { return }
        Task { await refresh() }
    }

    /// The tab is on screen: remember that, so launches look too.
    func activate() {
        guard live, let defaults, !defaults.bool(forKey: Self.activeKey) else { return }
        defaults.set(true, forKey: Self.activeKey)
    }

    /// App launch, or the claudex menu switched back on.
    func startIfActive() {
        guard live, defaults?.bool(forKey: Self.activeKey) == true else { return }
        Task { await refresh() }
    }

    // MARK: Snapshot helpers

    /// Snapshot states only.
    func showSamplePartial() { snapshot = SampleData.usageSnapshotPartial }

    func showSampleEmpty() {
        snapshot = UsageSnapshot(monthStart: SampleData.usageSnapshot.monthStart, lastMonthStart: SampleData.usageSnapshot.lastMonthStart,
                                 updatedAt: SampleData.now, noData: true)
    }

    func showSampleLoading() {
        snapshot = nil
        loading = true
    }
}
