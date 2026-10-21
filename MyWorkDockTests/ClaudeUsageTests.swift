import XCTest
@testable import MyWorkDock

/// Synthetic transcript lines, shaped like Claude Code's.
enum UsageFixture {
    static func line(_ id: String, at stamp: String, model: String = "claude-opus-4-8", input: Int = 0, cw5m: Int = 0, cw1h: Int = 0,
                     cr: Int = 0, out: Int = 0) -> String {
        #"{"type":"assistant","uuid":"u-\#(id)-\#(out)","timestamp":"\#(stamp)","sessionId":"s1","isSidechain":false,"message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cw5m + cw1h),"cache_read_input_tokens":\#(cr),"output_tokens":\#(out),"cache_creation":{"ephemeral_5m_input_tokens":\#(cw5m),"ephemeral_1h_input_tokens":\#(cw1h)}}}}"#
    }

    static func data(_ lines: String...) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    static func date(_ iso: String) -> Date { Date(timeIntervalSince1970: TranscriptParser.epoch(iso: iso)!) }

    static func calendar(_ zone: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    static func call(_ id: String, at stamp: String, model: String = "claude-opus-4-8", tokens: TokenCounts) -> ParsedCall {
        ParsedCall(key: CallKey(id), t: date(stamp).timeIntervalSince1970, model: model, tokens: tokens)
    }
}

final class TranscriptParserTests: XCTestCase {
    func testReadsTokensModelTimeAndTheCacheSplit() throws {
        let line = UsageFixture.line("msg_1", at: "2026-10-21T17:23:13.500Z", input: 3, cw5m: 100, cw1h: 400, cr: 50_000, out: 20)
        let call = try XCTUnwrap(TranscriptParser.parse(UsageFixture.data(line)).first)
        XCTAssertEqual(call.model, "claude-opus-4-8")
        XCTAssertEqual(call.t, 1_792_603_393.5, accuracy: 0.001)
        XCTAssertEqual(call.tokens, TokenCounts(input: 3, cacheWrite5m: 100, cacheWrite1h: 400, cacheRead: 50_000, output: 20))
        XCTAssertEqual(call.tokens.total, 50_523)
        XCTAssertEqual(call.key, CallKey("msg_1"))
    }

    func testStreamedChunksOfOneMessageCountOnceWithTheFinalOutput() {
        let calls = TranscriptParser.parse(UsageFixture.data(
            UsageFixture.line("msg_1", at: "2026-10-21T17:23:13.000Z", input: 2, cw1h: 500, out: 7),
            UsageFixture.line("msg_2", at: "2026-10-21T17:23:20.000Z", out: 9),
            UsageFixture.line("msg_1", at: "2026-10-21T17:23:15.000Z", input: 2, cw1h: 500, out: 265)))
        XCTAssertEqual(calls.count, 2)
        let first = calls.first { $0.key == CallKey("msg_1") }
        XCTAssertEqual(first?.tokens.output, 265) // the last chunk's output, not the first's
        XCTAssertEqual(first?.tokens.input, 2) // the repeated fields are not added up
        XCTAssertEqual(first?.t ?? 0, UsageFixture.date("2026-10-21T17:23:13.000Z").timeIntervalSince1970, accuracy: 0.001) // the first chunk's time
    }

    func testSkipsWhatIsNotAClaudeAssistantCall() {
        let notAssistant = #"{"type":"user","timestamp":"2026-10-21T17:23:13Z","message":{"role":"user","content":"my usage and the assistant"}}"#
        let synthetic = UsageFixture.line("msg_s", at: "2026-10-21T17:23:13Z", model: "<synthetic>", out: 5)
        let otherProvider = UsageFixture.line("msg_o", at: "2026-10-21T17:23:13Z", model: "stepfun/step-3.5-flash:free", out: 5)
        let noUsage = #"{"type":"assistant","timestamp":"2026-10-21T17:23:13Z","message":{"id":"m","model":"claude-opus-4-8","content":[]}}"#
        let noTime = #"{"type":"assistant","message":{"id":"m","model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":1}}}"#
        let broken = #"{"type":"assistant","message":{"usage":{"input_tokens":1,"#
        XCTAssertEqual(TranscriptParser.parse(UsageFixture.data(notAssistant, synthetic, otherProvider, noUsage, noTime, broken, "", "not json at all")), [])
    }

    func testAMessageIdFallsBackToTheLineUUID() throws {
        let line = #"{"type":"assistant","uuid":"abc","timestamp":"2026-10-21T17:23:13Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":4,"output_tokens":6}}}"#
        let call = try XCTUnwrap(TranscriptParser.parse(UsageFixture.data(line)).first)
        XCTAssertEqual(call.key, CallKey("abc"))
        XCTAssertEqual(call.tokens, TokenCounts(input: 4, output: 6))
    }

    func testACacheWriteWithoutASplitIsPricedAsOneHourAndTheRemainderToo() throws {
        let plain = #"{"type":"assistant","timestamp":"2026-10-21T17:23:13Z","message":{"id":"a","model":"claude-sonnet-5-5","usage":{"cache_creation_input_tokens":900,"output_tokens":1}}}"#
        let partial = #"{"type":"assistant","timestamp":"2026-10-21T17:23:13Z","message":{"id":"b","model":"claude-sonnet-5-5","usage":{"cache_creation_input_tokens":900,"cache_creation":{"ephemeral_5m_input_tokens":300,"ephemeral_1h_input_tokens":100}}}}"#
        let calls = TranscriptParser.parse(UsageFixture.data(plain, partial))
        XCTAssertEqual(calls.first { $0.key == CallKey("a") }?.tokens, TokenCounts(cacheWrite1h: 900, output: 1))
        XCTAssertEqual(calls.first { $0.key == CallKey("b") }?.tokens, TokenCounts(cacheWrite5m: 300, cacheWrite1h: 600))
    }

    func testALineCutShortIsNotCounted() {
        // The scanner stops at the last newline, so a half-written line never reaches the parser; if one did, it would not parse.
        let whole = UsageFixture.line("msg_1", at: "2026-10-21T17:23:13Z", out: 3)
        XCTAssertEqual(TranscriptParser.parse(Data(whole.utf8)).count, 1)
        XCTAssertEqual(TranscriptParser.parse(Data(String(whole.dropLast(20)).utf8)).count, 0)
    }

    func testIsoTimestampsMatchTheSystemParser() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for stamp in ["2026-10-21T17:23:13.500Z", "2028-02-29T23:59:59.999Z", "2026-12-31T23:59:59.001Z", "1970-01-01T00:00:00.000Z", "2000-03-01T00:00:00.000Z"] {
            XCTAssertEqual(try XCTUnwrap(TranscriptParser.epoch(iso: stamp)), try XCTUnwrap(formatter.date(from: stamp)).timeIntervalSince1970, accuracy: 0.0005, stamp)
        }
        XCTAssertEqual(TranscriptParser.epoch(iso: "2026-12-31T23:59:59Z"), 1_798_761_599)
        XCTAssertEqual(TranscriptParser.epoch(iso: "1970-01-01T00:00:00Z"), 0)
        XCTAssertEqual(try XCTUnwrap(TranscriptParser.epoch(iso: "2026-10-21T17:23:13+05:30")), 1_792_583_593, accuracy: 0.001) // another offset: slow path
        XCTAssertNil(TranscriptParser.epoch(iso: "yesterday"))
        XCTAssertNil(TranscriptParser.epoch(iso: ""))
        XCTAssertNil(TranscriptParser.epoch(iso: "2026-10-2xT17:23:13Z"))
    }

    func testCallKeyIsStableAcrossLaunchesAndRoundTrips() throws {
        XCTAssertEqual(CallKey("msg_abc").raw, 0xc0ee_a3c5_fa22_6569) // FNV-1a 64: never Swift's per-launch hashValue
        XCTAssertEqual(CallKey("").raw, 0xcbf2_9ce4_8422_2325)
        let saved = try JSONEncoder().encode([CallKey("msg_abc")])
        XCTAssertEqual(try JSONDecoder().decode([CallKey].self, from: saved), [CallKey("msg_abc")])
        XCTAssertThrowsError(try JSONDecoder().decode([CallKey].self, from: Data(#"["zz"]"#.utf8)))
    }
}

final class UsagePricingTests: XCTestCase {
    func testEachKindOfTokenIsPricedAtItsOwnRate() {
        let million = TokenCounts(input: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000, output: 1_000_000)
        // Opus 4.8: input 5, 5-minute write 5 x 1.25, 1-hour write 5 x 2, read 0.5, output 25
        XCTAssertEqual(UsagePricing.cost(million, model: "claude-opus-4-8"), 5 + 6.25 + 10 + 0.5 + 25, accuracy: 1e-9)
        XCTAssertEqual(UsagePricing.cost(TokenCounts(), model: "claude-opus-4-8"), 0)
    }

    func testAHeavilyCachedSessionPricesByHand() {
        // Cache reads dominate a long session: 26M x $0.50 + 87k x $25 + 180k x $10 + 3k x $5, per million.
        let t = TokenCounts(input: 3_000, cacheWrite1h: 180_000, cacheRead: 26_000_000, output: 87_000)
        XCTAssertEqual(UsagePricing.cost(t, model: "claude-opus-4-8"), 13.0 + 2.175 + 1.8 + 0.015, accuracy: 1e-9)
    }

    func testTheLongestVersionWinsAndASuffixDoesNotMatter() {
        XCTAssertEqual(UsagePricing.price(for: "claude-opus-5-5").input, 4)
        XCTAssertEqual(UsagePricing.price(for: "claude-opus-5").input, 5)
        XCTAssertEqual(UsagePricing.price(for: "claude-opus-5-5-20261101").input, 4)
        XCTAssertEqual(UsagePricing.price(for: "claude-haiku-4-5-20251001").output, 5)
        XCTAssertEqual(UsagePricing.price(for: "CLAUDE-SONNET-4-6").output, 15)
    }

    func testAnUnlistedVersionIsPricedAsItsFamilysCurrentModel() {
        XCTAssertEqual(UsagePricing.price(for: "claude-opus-9"), UsagePricing.price(for: "claude-opus-5-5"))
        XCTAssertEqual(UsagePricing.price(for: "claude-haiku-9"), UsagePricing.price(for: "claude-haiku-4-5"))
        XCTAssertEqual(UsagePricing.price(for: "claude-mystery-1"), UsagePricing.price(for: "claude-sonnet-5-5"))
    }
}

final class UsageLedgerTests: XCTestCase {
    private let now = UsageFixture.date("2026-10-21T18:00:00Z") // 23:30 on 21 Oct in India
    private let utc = UsageFixture.calendar()
    private func out(_ n: Int) -> TokenCounts { TokenCounts(output: n) }

    func testACallIsCountedOnceNoMatterHowOftenOrWhereItIsSeen() {
        var ledger = UsageLedger()
        let call = UsageFixture.call("m1", at: "2026-10-21T10:00:00Z", tokens: out(1_000_000))
        XCTAssertTrue(ledger.add([call], now: now, calendar: utc))
        XCTAssertFalse(ledger.add([call], now: now, calendar: utc)) // a rescan, or a resumed session's copy of the line
        XCTAssertEqual(ledger.days["2026-10-21"]?["claude-opus-4-8"]?.output, 1_000_000)
    }

    func testALaterChunkOfARecentCallRaisesItsTokensWithoutDoubleCounting() {
        var ledger = UsageLedger()
        ledger.add([UsageFixture.call("m1", at: "2026-10-21T17:00:00Z", tokens: TokenCounts(input: 2, cacheWrite1h: 500, output: 7))], now: now, calendar: utc)
        ledger.add([UsageFixture.call("m1", at: "2026-10-21T17:00:00Z", tokens: TokenCounts(input: 2, cacheWrite1h: 500, output: 265))], now: now, calendar: utc)
        XCTAssertEqual(ledger.days["2026-10-21"]?["claude-opus-4-8"], TokenCounts(input: 2, cacheWrite1h: 500, output: 265))
        XCTAssertEqual(ledger.recent.first?.tokens.output, 265)
        XCTAssertEqual(ledger.recent.count, 1)
    }

    func testDaysFollowTheCalendarsTimeZone() {
        let call = UsageFixture.call("m1", at: "2026-10-21T20:00:00Z", tokens: out(5))
        var india = UsageLedger(), utcLedger = UsageLedger()
        india.add([call], now: now, calendar: UsageFixture.calendar("Asia/Kolkata"))
        utcLedger.add([call], now: now, calendar: utc)
        XCTAssertEqual(Array(india.days.keys), ["2026-10-22"]) // 01:30 the next morning
        XCTAssertEqual(Array(utcLedger.days.keys), ["2026-10-21"])
    }

    func testSnapshotSplitsFiveHoursTodayThisMonthAndLastMonth() {
        var ledger = UsageLedger()
        let million = out(1_000_000) // $25 on Opus 4.8
        ledger.add([UsageFixture.call("a", at: "2026-10-21T17:00:00Z", tokens: million), // an hour ago
                    UsageFixture.call("b", at: "2026-10-21T12:30:00Z", tokens: million), // 5.5 h ago: today, outside the five hours
                    UsageFixture.call("c", at: "2026-10-02T06:00:00Z", tokens: million), // this month only
                    UsageFixture.call("d", at: "2026-09-25T06:00:00Z", tokens: million), // last month
                    UsageFixture.call("e", at: "2026-08-30T06:00:00Z", tokens: million)], // neither
                   now: now, calendar: utc)
        let s = ledger.snapshot(now: now, calendar: utc)
        XCTAssertEqual(s.fiveHours.tokens.total, 1_000_000)
        XCTAssertEqual(s.fiveHours.cost, 25, accuracy: 1e-9)
        XCTAssertEqual(s.windowSince, UsageFixture.date("2026-10-21T17:00:00Z"))
        XCTAssertEqual(s.today.tokens.total, 2_000_000)
        XCTAssertEqual(s.month.tokens.total, 3_000_000)
        XCTAssertEqual(s.month.cost, 75, accuracy: 1e-9)
        XCTAssertEqual(s.lastMonth.tokens.total, 1_000_000)
        XCTAssertEqual(s.monthStart, UsageFixture.date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(s.lastMonthStart, UsageFixture.date("2026-09-01T00:00:00Z"))
    }

    func testTheFiveHoursRollWithTheClock() {
        var ledger = UsageLedger()
        ledger.add([UsageFixture.call("a", at: "2026-10-21T17:00:00Z", tokens: out(10))], now: now, calendar: utc)
        XCTAssertEqual(ledger.snapshot(now: now.addingTimeInterval(3 * 3600), calendar: utc).fiveHours.tokens.total, 10) // 4 h old
        let later = ledger.snapshot(now: now.addingTimeInterval(4 * 3600 + 1), calendar: utc) // 5 h old, still the 21st in UTC
        XCTAssertEqual(later.fiveHours.tokens.total, 0)
        XCTAssertNil(later.windowSince)
        XCTAssertEqual(later.today.tokens.total, 10)
        let overnight = ledger.snapshot(now: now.addingTimeInterval(7 * 3600), calendar: utc) // 01:00 UTC on the 22nd
        XCTAssertEqual(overnight.today.tokens.total, 0)
        XCTAssertEqual(overnight.month.tokens.total, 10)
    }

    func testCostIsPricedPerModel() {
        var ledger = UsageLedger()
        ledger.add([UsageFixture.call("a", at: "2026-10-21T10:00:00Z", model: "claude-opus-4-8", tokens: out(1_000_000)),
                    UsageFixture.call("b", at: "2026-10-21T10:01:00Z", model: "claude-haiku-4-5-20251001", tokens: out(1_000_000))], now: now, calendar: utc)
        XCTAssertEqual(ledger.snapshot(now: now, calendar: utc).today.cost, 25 + 5, accuracy: 1e-9)
    }

    // MARK: Coverage: which months can be trusted to be complete

    private func at(_ iso: String) -> Date { UsageFixture.date(iso) }

    func testTheFirstLookCoversTheThirtyDaysThatTranscriptsSurvive() {
        var ledger = UsageLedger()
        XCTAssertNil(ledger.completeFrom(monthStart: at("2026-09-01T00:00:00Z"), calendar: utc)) // never looked: nothing to say
        XCTAssertTrue(ledger.noteScan(now: now)) // 21 Oct 18:00 UTC: everything since 21 Sep 18:00 is certain
        // September began before that. Its first day that is covered whole is the 22nd.
        XCTAssertEqual(ledger.completeFrom(monthStart: at("2026-09-01T00:00:00Z"), calendar: utc), at("2026-09-22T00:00:00Z"))
        // October began within those 30 days: nothing of it can have been lost.
        XCTAssertNil(ledger.completeFrom(monthStart: at("2026-10-01T00:00:00Z"), calendar: utc))
        let s = ledger.snapshot(now: now, calendar: utc)
        XCTAssertNil(s.monthPartialFrom)
        XCTAssertEqual(s.lastMonthPartialFrom, at("2026-09-22T00:00:00Z"))
    }

    func testCoverageStartingAtMidnightIsCompleteFromThatDay() {
        var ledger = UsageLedger()
        ledger.noteScan(now: at("2026-10-21T00:00:00Z")) // minus 30 days is exactly 21 Sep 00:00
        XCTAssertEqual(ledger.completeFrom(monthStart: at("2026-09-01T00:00:00Z"), calendar: utc), at("2026-09-21T00:00:00Z"))
    }

    func testLooksLessThanThirtyDaysApartLeaveNoHole() {
        var ledger = UsageLedger()
        ledger.noteScan(now: at("2026-09-01T12:00:00Z"))
        let covered = ledger.coveredFrom
        XCTAssertFalse(ledger.noteScan(now: at("2026-09-15T12:00:00Z")))
        XCTAssertFalse(ledger.noteScan(now: at("2026-10-01T12:00:00Z"))) // exactly 30 days after the one before: still nothing missed
        XCTAssertEqual(ledger.coveredFrom, covered)
        XCTAssertEqual(ledger.lastScan, at("2026-10-01T12:00:00Z").timeIntervalSince1970)
        XCTAssertEqual(ledger.completeFrom(monthStart: at("2026-08-01T00:00:00Z"), calendar: utc), at("2026-08-03T00:00:00Z")) // covered from 2 Aug 12:00
        XCTAssertNil(ledger.completeFrom(monthStart: at("2026-09-01T00:00:00Z"), calendar: utc))
    }

    func testALookMoreThanThirtyDaysAfterTheLastOneStartsCoverageAgain() {
        var ledger = UsageLedger()
        ledger.noteScan(now: at("2026-09-01T12:00:00Z")) // tab first opened on 1 Sep, then not again
        XCTAssertTrue(ledger.noteScan(now: at("2026-10-21T18:00:00Z"))) // calls from 2 Sep to 21 Sep may have been deleted unseen
        XCTAssertEqual(ledger.coveredFrom, at("2026-09-21T18:00:00Z").timeIntervalSince1970)
        // September is no longer called complete just because the first look was on its 1st.
        XCTAssertEqual(ledger.completeFrom(monthStart: at("2026-09-01T00:00:00Z"), calendar: utc), at("2026-09-22T00:00:00Z"))
    }

    func testAMonthThatEndedBeforeCoverageHasNoCompleteDay() {
        var ledger = UsageLedger()
        ledger.noteScan(now: at("2026-10-22T12:00:00Z")) // covered from 22 Sep
        let from = ledger.completeFrom(monthStart: at("2026-08-01T00:00:00Z"), calendar: utc)
        XCTAssertEqual(from, at("2026-09-23T00:00:00Z"))
        XCTAssertGreaterThanOrEqual(from ?? .distantPast, at("2026-09-01T00:00:00Z")) // on or after August's end: nothing of it is vouched for
    }

    func testTheClockGoingBackwardsDoesNotShrinkTheLastScanOrOpenAHole() {
        var ledger = UsageLedger()
        ledger.noteScan(now: at("2026-10-21T18:00:00Z"))
        let covered = ledger.coveredFrom
        XCTAssertFalse(ledger.noteScan(now: at("2026-10-01T18:00:00Z")))
        XCTAssertEqual(ledger.coveredFrom, covered)
        XCTAssertEqual(ledger.lastScan, at("2026-10-21T18:00:00Z").timeIntervalSince1970)
    }

    func testNothingIsPartialBeforeTheFirstLook() {
        let s = UsageLedger().snapshot(now: now, calendar: utc)
        XCTAssertNil(s.monthPartialFrom)
        XCTAssertNil(s.lastMonthPartialFrom)
    }

    func testPruneForgetsOldRecentCallsAndIdsButKeepsTheTotals() {
        var ledger = UsageLedger()
        let old = UsageFixture.date("2026-06-01T06:00:00Z") // 142 days before `now`
        ledger.add([ParsedCall(key: CallKey("old"), t: old.timeIntervalSince1970, model: "claude-opus-4-8", tokens: out(4)),
                    UsageFixture.call("new", at: "2026-10-21T17:00:00Z", tokens: out(6))], now: now, calendar: utc)
        XCTAssertEqual(ledger.seen.count, 2)
        XCTAssertTrue(ledger.prune(now: now.addingTimeInterval(1))) // the old id goes at the first prune after it was added
        XCTAssertEqual(ledger.seen.count, 1)
        XCTAssertEqual(ledger.recent.count, 1)
        XCTAssertTrue(ledger.prune(now: now.addingTimeInterval(7 * 3600))) // six hours on, the recent call is dropped
        XCTAssertEqual(ledger.recent.count, 0)
        XCTAssertEqual(ledger.days["2026-06-01"]?["claude-opus-4-8"]?.output, 4)
        XCTAssertEqual(ledger.days["2026-10-21"]?["claude-opus-4-8"]?.output, 6)
    }

    func testTheLedgerSurvivesSavingAndLoading() throws {
        var ledger = UsageLedger()
        ledger.noteScan(now: now)
        ledger.files["/p/a.jsonl"] = FileMark(offset: 10, size: 20, mtime: 30, head: "ab12", headLength: 7)
        ledger.add([UsageFixture.call("m1", at: "2026-10-21T17:00:00Z", tokens: TokenCounts(input: 1, cacheWrite5m: 2, cacheWrite1h: 3, cacheRead: 4, output: 5)),
                    UsageFixture.call("m2", at: "2026-09-02T06:00:00Z", tokens: out(9))], now: now, calendar: utc)
        var loaded = try JSONDecoder().decode(UsageLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(loaded, ledger)
        // The ids came back: the same lines add nothing, and a recent call can still grow.
        XCTAssertFalse(loaded.add([UsageFixture.call("m2", at: "2026-09-02T06:00:00Z", tokens: out(9))], now: now, calendar: utc))
        XCTAssertTrue(loaded.add([UsageFixture.call("m1", at: "2026-10-21T17:00:00Z", tokens: TokenCounts(input: 1, cacheWrite5m: 2, cacheWrite1h: 3, cacheRead: 4, output: 50))], now: now, calendar: utc))
        XCTAssertEqual(loaded.days["2026-10-21"]?["claude-opus-4-8"]?.output, 50)
    }

    func testAnOlderOrEmptyFileLoadsWithDefaults() throws {
        let ledger = try JSONDecoder().decode(UsageLedger.self, from: Data("{}".utf8))
        XCTAssertEqual(ledger, UsageLedger())
        let partial = try JSONDecoder().decode(UsageLedger.self, from: Data(#"{"lastScan":5,"days":{"2026-10-01":{"claude-opus-4-8":{"output":3}}}}"#.utf8))
        XCTAssertEqual(partial.lastScan, 5)
        XCTAssertEqual(partial.days["2026-10-01"]?["claude-opus-4-8"], TokenCounts(output: 3)) // fields a version did not write read as 0
    }

    func testTwoSavedEntriesForOneCallLoadAsOneWithTheLargerCounts() throws {
        let key = String(CallKey("m1").raw, radix: 16)
        func entry(_ out: Int) -> String { #"{"key":"\#(key)","t":1792600000,"model":"claude-opus-4-8","tokens":{"output":\#(out)}}"# }
        let ledger = try JSONDecoder().decode(UsageLedger.self, from: Data(#"{"recent":[\#(entry(7)),\#(entry(9)),\#(entry(8))]}"#.utf8))
        XCTAssertEqual(ledger.recent.count, 1) // was a crash: a dictionary built from duplicate keys traps
        XCTAssertEqual(ledger.recent.first?.tokens.output, 9)
    }

    func testANegativeSavedCountLoadsAsZero() throws {
        let ledger = try JSONDecoder().decode(UsageLedger.self, from: Data(#"{"days":{"2026-10-01":{"claude-opus-4-8":{"output":-5,"input":4}}}}"#.utf8))
        XCTAssertEqual(ledger.days["2026-10-01"]?["claude-opus-4-8"], TokenCounts(input: 4))
    }
}
