import XCTest
@testable import MyWorkDock

final class UsageFormatTests: XCTestCase {
    func testCostHasThousandsCommasAndTwoDecimals() {
        XCTAssertEqual(UsageFormat.cost(0), "$0.00")
        XCTAssertEqual(UsageFormat.cost(5), "$5.00")
        XCTAssertEqual(UsageFormat.cost(0.07), "$0.07")
        XCTAssertEqual(UsageFormat.cost(999.994), "$999.99")
        XCTAssertEqual(UsageFormat.cost(999.995), "$1,000.00") // rounds up through the thousand
        XCTAssertEqual(UsageFormat.cost(6_993.214), "$6,993.21")
        XCTAssertEqual(UsageFormat.cost(1_234_567.8), "$1,234,567.80") // never lakh grouping, whatever the Mac's region
        XCTAssertEqual(UsageFormat.cost(-3), "$0.00")
    }

    func testTokensKeepThreeSignificantDigitsAndMoveUpAUnitBeforeRoundingToOneThousand() {
        XCTAssertEqual(UsageFormat.tokens(0), "0")
        XCTAssertEqual(UsageFormat.tokens(980), "980")
        XCTAssertEqual(UsageFormat.tokens(1_000), "1.0k")
        XCTAssertEqual(UsageFormat.tokens(99_949), "99.9k")
        XCTAssertEqual(UsageFormat.tokens(99_950), "100k")
        XCTAssertEqual(UsageFormat.tokens(612_000), "612k")
        XCTAssertEqual(UsageFormat.tokens(999_499), "999k")
        XCTAssertEqual(UsageFormat.tokens(999_500), "1.0M")
        XCTAssertEqual(UsageFormat.tokens(497_100_000), "497M")
        XCTAssertEqual(UsageFormat.tokens(99_900_000), "99.9M")
        XCTAssertEqual(UsageFormat.tokens(999_500_000), "1.00B")
        XCTAssertEqual(UsageFormat.tokens(14_463_000_000), "14.46B")
    }

    func testTheSplitNamesTheFourKindsInTheTokenMetricsOrder() {
        let t = TokenCounts(input: 3_000, cacheWrite5m: 1_000_000, cacheWrite1h: 2_000_000, cacheRead: 487_600_000, output: 2_100_000)
        XCTAssertEqual(UsageFormat.split(t), "input 3.0k · cache write 3.0M · cache read 488M · output 2.1M")
    }
}

final class UsageCardsTests: XCTestCase {
    private let utc = UsageFixture.calendar()
    private let us = Locale(identifier: "en_US")

    private func snapshot(partial: Date? = nil, monthPartial: Date? = nil, noData: Bool = false) -> UsageSnapshot {
        // `out` million output tokens and 100x as many cache reads: $75 per million of `out` on Opus 4.8
        func f(_ out: Int) -> UsageFigures {
            var x = UsageFigures()
            x.add(TokenCounts(cacheRead: out * 100, output: out), model: "claude-opus-4-8")
            return x
        }
        return UsageSnapshot(fiveHours: f(1_000_000), windowSince: UsageFixture.date("2026-10-21T13:42:00Z"), today: f(2_000_000), month: f(30_000_000), lastMonth: f(40_000_000),
                             monthStart: UsageFixture.date("2026-10-01T00:00:00Z"), lastMonthStart: UsageFixture.date("2026-09-01T00:00:00Z"),
                             monthPartialFrom: monthPartial, lastMonthPartialFrom: partial, updatedAt: UsageFixture.date("2026-10-21T18:00:00Z"), noData: noData)
    }

    func testFourCardsInTheOrderOfTheTab() {
        let cards = UsageCards.make(snapshot(), calendar: utc, locale: us)
        XCTAssertEqual(cards.map(\.title), ["Last 5 hours", "Today", "This month", "Last month"])
        XCTAssertEqual(cards.map(\.id), ["five", "today", "month", "last"])
        XCTAssertEqual(cards[0].cost, "$75.00") // 1M output x $25 + 100M cache read x $0.50
        XCTAssertEqual(cards[0].tokens, "101M tokens")
        XCTAssertEqual(cards[2].cost, "$2,250.00")
        XCTAssertTrue(cards[0].caption.hasPrefix("since 1:42"), cards[0].caption)
        XCTAssertTrue(cards[1].caption.contains("21") && cards[1].caption.contains("Oct"), cards[1].caption)
        XCTAssertEqual(cards[2].caption, "October 2026")
        XCTAssertEqual(cards[3].caption, "September 2026")
        XCTAssertFalse(cards[3].partial)
        XCTAssertNil(cards[3].help)
        XCTAssertTrue(cards.allSatisfy { !$0.split.isEmpty })
    }

    func testAPartialLastMonthSaysFromWhenAndExplainsItself() {
        let last = UsageCards.make(snapshot(partial: UsageFixture.date("2026-09-21T00:00:00Z")), calendar: utc, locale: us)[3]
        XCTAssertTrue(last.partial)
        XCTAssertTrue(last.caption.hasPrefix("partial · from"), last.caption)
        XCTAssertTrue(last.caption.contains("Sep") && last.caption.contains("21"), last.caption)
        XCTAssertEqual(last.help, UsageCards.partialHelp)
    }

    func testAMonthThatEndedBeforeAnythingWasTrackedSaysNotTracked() {
        let last = UsageCards.make(snapshot(partial: UsageFixture.date("2026-10-02T00:00:00Z")), calendar: utc, locale: us)[3]
        XCTAssertTrue(last.partial)
        XCTAssertEqual(last.caption, "not tracked") // no day of September can be vouched for, so no "from" date
        XCTAssertEqual(last.help, UsageCards.untrackedHelp)
    }

    func testThisMonthIsMarkedToo() {
        let cards = UsageCards.make(snapshot(monthPartial: UsageFixture.date("2026-10-03T00:00:00Z")), calendar: utc, locale: us)
        XCTAssertTrue(cards[2].partial)
        XCTAssertTrue(cards[2].caption.hasPrefix("partial · from"), cards[2].caption)
        XCTAssertTrue(cards[2].caption.contains("3"), cards[2].caption)
        XCTAssertFalse(cards[3].partial)
    }

    func testNothingShowsADashAndSaysWhy() {
        var s = snapshot()
        s.fiveHours = UsageFigures()
        s.windowSince = nil
        s.today = UsageFigures()
        s.lastMonth = UsageFigures()
        let cards = UsageCards.make(s, calendar: utc, locale: us)
        XCTAssertEqual(cards.map(\.cost), ["—", "—", UsageFormat.cost(s.month.cost), "—"])
        XCTAssertEqual(cards[0].tokens, "no usage in the last 5 hours")
        XCTAssertEqual(cards[0].caption, "rolling window")
        XCTAssertEqual(cards[1].tokens, "no usage yet today")
        XCTAssertEqual(cards[3].tokens, "no data for last month")
        XCTAssertEqual(cards[0].split, "")
    }
}

@MainActor
final class ClaudeUsageStoreTests: XCTestCase {
    private var dir: URL!
    private var suite: String!
    private let now = UsageFixture.date("2026-10-21T18:00:00Z")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("projects/-p"), withIntermediateDirectories: true)
        suite = "claude-usage-tests-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func store(engines: Counter = Counter()) -> ClaudeUsageStore {
        let root = dir.appendingPathComponent("projects")
        let s = ClaudeUsageStore(makeEngine: { engines.n += 1; return UsageEngine(root: root, stateURL: nil) }, defaults: UserDefaults(suiteName: suite))
        s.now = { [now] in now }
        s.calendar = UsageFixture.calendar()
        return s
    }

    final class Counter { var n = 0 }

    func testTheSampleStoreNeverTouchesDisk() async {
        let s = ClaudeUsageStore(sample: true)
        XCTAssertNotNil(s.snapshot)
        XCTAssertEqual(s.cards.count, 4)
        XCTAssertEqual(s.freshLabel, "just now")
        await s.refresh()
        XCTAssertFalse(s.loading)
        s.activate()
        s.startIfActive()
        XCTAssertEqual(s.snapshot, SampleData.usageSnapshot)
    }

    func testRefreshFillsTheSnapshotFromTheTranscripts() async throws {
        try Data((UsageFixture.line("m1", at: "2026-10-21T10:00:00Z", out: 1_000_000) + "\n").utf8)
            .write(to: dir.appendingPathComponent("projects/-p/s1.jsonl"))
        let s = store()
        XCTAssertNil(s.snapshot)
        XCTAssertEqual(s.freshLabel, "not loaded")
        await s.refresh()
        let snap = try XCTUnwrap(s.snapshot)
        XCTAssertEqual(snap.today.tokens.total, 1_000_000)
        XCTAssertEqual(snap.today.cost, 25, accuracy: 1e-9)
        XCTAssertEqual(s.cards[1].tokens, "1.0M tokens")
        XCTAssertEqual(s.freshLabel, "just now")
        XCTAssertFalse(s.loading)
    }

    func testTheEngineIsOnlyBuiltWhenSomethingLooks() async {
        let engines = Counter()
        let s = store(engines: engines)
        s.activate()
        _ = s.cards
        XCTAssertEqual(engines.n, 0)
        await s.refresh()
        await s.refresh()
        XCTAssertEqual(engines.n, 1)
    }

    func testOpeningTheTabIsRememberedAndLaunchesThenLookByThemselves() async throws {
        let engines = Counter()
        let first = store(engines: engines)
        first.startIfActive() // never opened: a Mac that only uses the claudex tabs reads nothing
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(first.snapshot)
        XCTAssertEqual(engines.n, 0)

        first.activate() // the tab was opened once

        let second = store(engines: engines) // the next launch
        second.startIfActive()
        for _ in 0..<40 where second.snapshot == nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(second.snapshot)
        XCTAssertEqual(engines.n, 1)
    }

    func testAMissingTranscriptFolderIsNoDataNotAnError() async throws {
        try FileManager.default.removeItem(at: dir.appendingPathComponent("projects"))
        let s = store()
        await s.refresh()
        XCTAssertEqual(s.snapshot?.noData, true)
        XCTAssertNil(s.saveError)
    }
}
