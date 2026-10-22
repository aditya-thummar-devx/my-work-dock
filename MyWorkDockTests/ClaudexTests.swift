import XCTest
@testable import MyWorkDock

final class ClaudexParserTests: XCTestCase {
    private let usage = """

      Usage   ·   weekly limit is the one that bites

      ┌───┬─────────┬────────┬─────────────────────────────────┬─────────────────────────────────┬─────────┐
      │   │ ACCOUNT │ TIER   │ SESSION                         │ WEEK                            │ UPDATED │
      ├───┼─────────┼────────┼─────────────────────────────────┼─────────────────────────────────┼─────────┤
      │ ○ │ amy     │ Max 5x │ █░░░░░░░░░   9%  Aug 20 1:09am  │ █░░░░░░░░░   9%  Aug 23 12:29pm │ live    │
      │ ● │ bob     │ Team   │ ░░░░░░░░░░   —                  │ ██████████ 100%  Aug 21 9:29am  │ live    │
      └───┴─────────┴────────┴─────────────────────────────────┴─────────────────────────────────┴─────────┘
    """

    func testUsageTableAndNoReadingIsNotZero() throws {
        let rows = try XCTUnwrap(ClaudexParsers.usage(usage))
        XCTAssertEqual(rows.map(\.account), ["amy", "bob"])
        XCTAssertEqual(rows.map(\.active), [false, true])
        XCTAssertEqual(rows[0].session, Gauge(pct: 9, at: "Aug 20 1:09am"))
        XCTAssertEqual(rows[1].session, .none) // — means no reading, not 0 %
        XCTAssertEqual(rows[1].week, Gauge(pct: 100, at: "Aug 21 9:29am"))
        XCTAssertEqual(rows[0].tier, "Max 5x")
    }

    func testUnknownOutputAndErrorPagesAreNil() {
        XCTAssertNil(ClaudexParsers.usage("garbage"))
        XCTAssertNil(ClaudexParsers.usage("usage: claudex: error: unrecognized arguments: --json"))
        XCTAssertNil(ClaudexParsers.list(usage)) // a usage table is not a list table
        XCTAssertNil(ClaudexParsers.poolMembers("nothing here"))
        XCTAssertNil(ClaudexParsers.doctor("what? isn't a thing"))
    }

    func testListCurrentAndPoolStatus() throws {
        let list = """
          ┌───┬─────────┬──────────────────┬───────────┬──────┬────────┐
          │   │ ACCOUNT │ EMAIL            │ ORG       │ PLAN │ SAVED  │
          ├───┼─────────┼──────────────────┼───────────┼──────┼────────┤
          │ ● │ amy     │ amy@example.com  │ acme corp │ team │ 1d ago │
          └───┴─────────┴──────────────────┴───────────┴──────┴────────┘
        """
        let accounts = try XCTUnwrap(ClaudexParsers.list(list))
        XCTAssertEqual(accounts.first?.email, "amy@example.com")
        XCTAssertEqual(accounts.first?.org, "acme corp")

        let cur = try XCTUnwrap(ClaudexParsers.current("\n  ● amy\n    amy@example.com\n    acme corp  ·  team\n"))
        XCTAssertEqual(cur, CurrentAccount(account: "amy", email: "amy@example.com", org: "acme corp", plan: "team"))

        let status = try XCTUnwrap(ClaudexParsers.poolStatus("""
          Pool   ·   shared multi-account proxy

          ○ consuming   token-swap OFF · on your own token  · start with pool start
          ● sharing     your account is serving the pool  · managed by your pod lead / admin
        """))
        XCTAssertFalse(status.consuming.on)
        XCTAssertTrue(status.sharing.on)
        XCTAssertTrue(status.sharing.detail.hasPrefix("your account is serving the pool"))
    }

    func testDoctorChecksAccountsAndSummary() throws {
        let d = try XCTUnwrap(ClaudexParsers.doctor("""
          Doctor   ·   checking your setup

          ✓ macOS
          ✓ claude CLI   2.1.234 (Claude Code)
          ✗ autoswitch   disabled

          accounts:
          ✓ amy   token valid
          ✗ bob   token expired

          ● 2 ok
        """))
        XCTAssertEqual(d.checks.map(\.label), ["macOS", "claude CLI", "autoswitch"])
        XCTAssertEqual(d.checks[1].detail, "2.1.234 (Claude Code)")
        XCTAssertFalse(d.checks[2].ok)
        XCTAssertEqual(d.accounts.map(\.ok), [true, false])
        XCTAssertEqual(d.summary, "2 ok")
    }

    func testPoolMembersWithMinusSignAndMarker() throws {
        let m = try XCTUnwrap(ClaudexParsers.poolMembers("""
          Pool   ·   3 members

          ▶ ● amy.lee  · Max 5x · ● on
                session █░░░░░░░   9%  Aug 20 1:10am
                week    █░░░░░░░   9%  Aug 23 12:30pm   net +2482.3M
            ○ bob.ray  · Team · ● on
                session ░░░░░░░░   0%
                week    █████░░░  65%  Aug 23 6:30pm   net −489.6M
            ○ cy.dee  · Team · ○ off
                session ░░░░░░░░   —
        """))
        XCTAssertEqual(m.map(\.name), ["amy.lee", "bob.ray", "cy.dee"])
        XCTAssertEqual(m.map(\.marked), [true, false, false])
        XCTAssertEqual(m[0].netM, 2482.3)
        XCTAssertEqual(m[1].netM, -489.6) // U+2212 must become a real minus
        XCTAssertEqual(m[1].session, Gauge(pct: 0, at: nil))
        XCTAssertEqual(m[1].week, Gauge(pct: 65, at: "Aug 23 6:30pm"))
        XCTAssertFalse(m[2].sharing)
        XCTAssertEqual(m[2].session, .none)
    }

    func testMemberDetailBox() throws {
        let d = try XCTUnwrap(ClaudexParsers.memberDetail("""
        ╭─ amy.lee · Max 5x ───────────────────────────────────────────╮
        │  ▶ ● on   offline                                            │
        │            in       out      cache r    cache w    req       │
        │  own       11.1M    38.4M    5671.7M    282.7M     52717  my token → me │
        │  borrowed  2.6M     5.9M     1267.0M    45.0M      8947  from pool │
        ├──────────────────────────────────────────────────────────────┤
        │  net give/take  −1137.3M  ↓ taker                            │
        ├──────────────────────────────────────────────────────────────┤
        │  USAGE SPLIT  · headroom stale                               │
        │  5-hour   9% used  · resets 1:09am                           │
        │    who drove your traffic:                                   │
        │    amy.lee (you)  ██████████████████ 100%  123.7M           │
        │  week   72% used  · resets Aug 23 12:29pm                    │
        │    amy.lee (you)  █████████████████░  95%  720.9M           │
        │    bob.ray        █░░░░░░░░░░░░░░░░░   3%  21.2M            │
        │  shares are of observed proxy tokens, approximate            │
        ╰──────────────────────────────────────────────────────────────╯
        """))
        XCTAssertEqual(d.name, "amy.lee")
        XCTAssertEqual(d.state, "offline")
        XCTAssertTrue(d.sharing)
        XCTAssertEqual(d.flows.map(\.label), ["own", "borrowed"])
        XCTAssertEqual(d.flows[0].req, "52717")
        XCTAssertEqual(d.flows[0].note, "my token → me")
        XCTAssertEqual(d.netM, -1137.3)
        XCTAssertEqual(d.netDir, "taker")
        XCTAssertEqual(d.splitNote, "headroom stale")
        XCTAssertEqual(d.windows.map(\.label), ["5-hour", "week"])
        XCTAssertEqual(d.windows[0].resets, "1:09am")
        XCTAssertEqual(d.windows[1].drivers.map(\.name), ["amy.lee", "bob.ray"])
        XCTAssertEqual(d.windows[1].drivers[0].you, true)
        XCTAssertEqual(d.windows[1].drivers[1].tokens, "21.2M")
        XCTAssertEqual(d.footnote, "shares are of observed proxy tokens, approximate")
        XCTAssertNil(ClaudexParsers.memberDetail("╭─ amy · Team ─╮\n│ hello │"))
    }

    func testAccessBoxAndEmptyBox() throws {
        let a = try XCTUnwrap(ClaudexParsers.access("""
        ╭─ Access to your account ──── 2 people ─╮
        │  ● amy.lee     allowed                 │
        │  ● bob.ray     blocked                 │
        ╰────────────────────────────────────────╯
          allow / block / remove:  access allow <name>
        """))
        XCTAssertEqual(a, [AccessPerson(name: "amy.lee", allowed: true), AccessPerson(name: "bob.ray", allowed: false)])
        XCTAssertEqual(ClaudexParsers.access("╭─ Access to your account ─╮\n╰──╯"), [])
        XCTAssertNil(ClaudexParsers.access("no box here"))
    }
}

final class ClaudexSortTests: XCTestCase {
    private typealias K = ClaudexSort.Key
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!

    func testResetAtParsesDatedAndBareTimes() {
        let cal = Calendar.current
        let dated = ClaudexSort.resetAt("Oct 15 4:29am", now: now)
        XCTAssertEqual(cal.dateComponents([.month, .day, .hour, .minute], from: dated!), DateComponents(month: 10, day: 15, hour: 4, minute: 29))
        XCTAssertEqual(cal.component(.hour, from: ClaudexSort.resetAt("12:05am", now: now)!), 0) // 12am is hour 0
        XCTAssertEqual(cal.component(.hour, from: ClaudexSort.resetAt("12:05pm", now: now)!), 12)
        XCTAssertNil(ClaudexSort.resetAt(nil, now: now))
        XCTAssertNil(ClaudexSort.resetAt("whenever", now: now))
        // A December reset read in January is next December, not 11 months ago.
        let jan = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 2))!
        XCTAssertEqual(cal.component(.year, from: ClaudexSort.resetAt("Dec 30 1:00am", now: jan)!), 2027)
    }

    func testNoReadingSinksInBothDirections() {
        let rows = [K(name: "a", session: nil, week: nil, reset: nil), K(name: "b", session: 10, week: 20, reset: nil),
                    K(name: "c", session: 5, week: 90, reset: nil)]
        XCTAssertEqual(ClaudexSort.weekAsc.apply(rows) { $0 }.map(\.name), ["b", "c", "a"])
        XCTAssertEqual(ClaudexSort.weekDesc.apply(rows) { $0 }.map(\.name), ["c", "b", "a"])
        XCTAssertEqual(ClaudexSort.sessionAsc.apply(rows) { $0 }.map(\.name), ["c", "b", "a"])
        XCTAssertEqual(ClaudexSort.standard.apply(rows) { $0 }.map(\.name), ["a", "b", "c"])
        XCTAssertEqual(ClaudexSort.nameDesc.apply(rows) { $0 }.map(\.name), ["c", "b", "a"])
    }

    func testExpiringSoonAndBlend() {
        let d = { (day: Int) in Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9))! }
        let rows = [K(name: "late", session: 0, week: 10, reset: d(19)), K(name: "soon", session: 0, week: 90, reset: d(14)),
                    K(name: "mid", session: 0, week: 50, reset: d(16))]
        XCTAssertEqual(ClaudexSort.resetAsc.apply(rows) { $0 }.map(\.name), ["soon", "mid", "late"])
        // ranks: used asc late0 mid1 soon2, expiring soon0 mid1 late2 -> late 2, mid 2, soon 2; ties keep input order
        XCTAssertEqual(ClaudexSort.weekReset.apply(rows) { $0 }.map(\.name), ["late", "soon", "mid"])
    }
}

@MainActor
final class ClaudexStoreTests: XCTestCase {
    private func store() -> ClaudexStore { ClaudexStore(sample: true) }

    func testSampleCardsAreSortedByExpiringSoonAndNoReadingLast() {
        let s = store()
        XCTAssertEqual(s.accountCards.map(\.id), ["studio", "work", "aditya"])
        XCTAssertEqual(s.memberCards.map(\.id).prefix(3), ["ira.shah", "neel.joshi", "sana"])
        XCTAssertEqual(s.memberCards.map(\.id).suffix(2), ["mira.mehta", "arjun.dhar"])
        XCTAssertNil(s.memberCards.last?.session)
    }

    func testFiveXFilterAndUsingMarker() {
        let s = store()
        s.maxOnly = true
        XCTAssertTrue(s.memberCards.allSatisfy { $0.plan.contains("5x") })
        XCTAssertEqual(s.memberCards.first { $0.using }?.id, nil) // zoya (Team) is filtered out
        s.maxOnly = false
        XCTAssertEqual(s.memberCards.first { $0.using }?.id, "zoya.khan")
        XCTAssertEqual(s.memberCards.first { $0.mine }?.id, "aditya.thummar")
    }

    func testSwitchToMineFollowsTheTab() {
        let s = store()
        s.select(.pool)
        XCTAssertEqual(s.mineCommand, ["pool", "use", "aditya.thummar"]) // zoya is marked, not me
        s.select(.usage)
        XCTAssertEqual(s.mineCommand, ["switch", "aditya", "--force"]) // active account is `work`
        s.select(.health)
        XCTAssertNil(s.mineCommand)
    }

    func testWritesAskFirstWithTheExactCommandAndRejectUnknownNames() {
        let s = store()
        s.removeAccount("studio")
        XCTAssertEqual(s.confirmer.pending?.command, "claudex remove studio --force")
        XCTAssertTrue(s.confirmer.pending?.danger == true)
        s.confirmer.cancel()
        s.switchAccount("nobody")
        XCTAssertNil(s.confirmer.pending)
        s.toggleAccess("ira.shah")
        XCTAssertEqual(s.confirmer.pending?.command, "claudex access deny ira.shah")
        s.confirmer.cancel()
        s.togglePool()
        XCTAssertEqual(s.confirmer.pending?.command, "claudex pool start")
        s.confirmer.cancel()
        s.toggleAutoswitch()
        XCTAssertEqual(s.confirmer.pending?.command, "claudex autoswitch on") // sample has it disabled
    }

    /// Polls the main actor until `done` holds (the writes run in a Task the test cannot await directly).
    private func wait(_ done: () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testMemberCardIsBusyWhileItsWriteRuns() async {
        let s = store()
        s.findTool = { _ in "/bin/claudex" }
        s.runner = { _, _, _ in
            try? await Task.sleep(nanoseconds: 300_000_000)
            return ProcessResult(status: 0, out: "ok", err: "")
        }
        s.toggleAccess("ira.shah")
        XCTAssertNil(s.busyMember) // not until the sheet is confirmed
        s.confirmer.confirm()
        await wait { s.busyMember != nil }
        XCTAssertEqual(s.busyMember, "ira.shah")
        XCTAssertEqual(s.memberCards.filter(\.busy).map(\.id), ["ira.shah"])
        await wait { s.busyMember == nil }
        XCTAssertTrue(s.memberCards.allSatisfy { !$0.busy })
    }

    func testDetailLoadingSpansTheFetchAndClearsOnClose() async {
        let s = ClaudexStore()
        s.findTool = { _ in "/bin/claudex" }
        s.identityURL = URL(fileURLWithPath: "/nonexistent")
        s.runner = { _, args, _ in
            if args.first == "pool", args.dropFirst().first == "members" {
                return ProcessResult(status: 0, out: "  ▶ ● cy.dee  · Team · ● on\n        session █░░░░░░░   5%  2:00pm\n", err: "")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            return ProcessResult(status: 0, out: "no box", err: "")
        }
        await s.refresh(fresh: true)
        s.openDetail("cy.dee")
        await wait { s.detailLoading }
        XCTAssertTrue(s.detailLoading)
        await wait { !s.detailLoading }
        XCTAssertEqual(s.detail.raw, "no box")
        s.refreshDetail()
        await wait { s.detailLoading }
        XCTAssertTrue(s.detailLoading)
        s.closeDetail()
        XCTAssertFalse(s.detailLoading)
    }

    /// A store whose claudex prints canned text, so the peek can be checked against pool on / off.
    private func liveStore(poolOn: Bool) async -> ClaudexStore {
        let s = ClaudexStore()
        s.findTool = { _ in "/bin/claudex" }
        s.identityURL = URL(fileURLWithPath: "/nonexistent")
        s.runner = { _, args, _ in
            let text: String
            switch args.joined(separator: " ") {
            case "usage": text = """
                ┌───┬─────────┬────────┬────────────┬────────────┬─────────┐
                │   │ ACCOUNT │ TIER   │ SESSION    │ WEEK       │ UPDATED │
                ├───┼─────────┼────────┼────────────┼────────────┼─────────┤
                │ ○ │ amy     │ Max 5x │ █░░  9%  1:09am │ █░░  9%  Aug 23 12:29pm │ live │
                │ ● │ bob     │ Team   │ ██░  32%  11:39pm │ ███  87%  Aug 20 4:29am │ live │
                └───┴─────────┴────────┴────────────┴────────────┴─────────┘
                """
            case "pool status": text = "\(poolOn ? "●" : "○") consuming   token-swap \(poolOn ? "ON" : "OFF") · x\n● sharing     serving the pool\n"
            case "pool members": text = """
                  ▶ ● cy.dee  · Team · ● on
                        session █░░░░░░░   5%  2:00pm
                        week    █░░░░░░░  40%  Oct 19 1:29am   net +1.0M
                    ○ amy.lee  · Max 5x · ● on
                        session ░░░░░░░░   0%
                """
            default: text = ""
            }
            return ProcessResult(status: 0, out: text, err: "")
        }
        await s.refresh(fresh: true)
        return s
    }

    func testPeekIsPoolMemberWhenPoolOnElseTheActiveSSOAccount() async {
        let on = await liveStore(poolOn: true).peekData
        XCTAssertTrue(on.isPool)
        XCTAssertEqual(on.name, "cy.dee")
        XCTAssertEqual(on.bars.map(\.percent), [5, 40])
        XCTAssertEqual(on.bars[1].reset, "Oct 19") // week resets as a date

        let off = await liveStore(poolOn: false).peekData
        XCTAssertFalse(off.isPool)
        XCTAssertEqual(off.name, "bob") // the ● account of the SSO list
        XCTAssertEqual(off.bars.map(\.percent), [32, 87])
    }

    func testHasPeekNeedsAnAccountClaudexCanName() async {
        let pool = await liveStore(poolOn: true), sso = await liveStore(poolOn: false)
        XCTAssertTrue(pool.hasPeek)
        XCTAssertTrue(sso.hasPeek)

        // claudex is not installed: no account, so hover must not draw a made-up one.
        let missing = ClaudexStore()
        missing.findTool = { _ in nil }
        missing.identityURL = URL(fileURLWithPath: "/nonexistent")
        await missing.refresh(fresh: true)
        XCTAssertFalse(missing.hasPeek)
        XCTAssertEqual(missing.peekData.name, "claudex") // the fallback the peek no longer draws
        XCTAssertEqual(missing.peekData.bars.map(\.percent), [nil, nil])
    }

    func testHealthCountsAndLabels() {
        let s = store()
        XCTAssertEqual(s.healthCounts.ok, 12)
        XCTAssertEqual(s.healthCounts.warn, 2)
        XCTAssertEqual(s.freshLabel, "just now")
        XCTAssertEqual(s.footer, "Reads cached 60s · writes ask first")
    }

    func testCapturesAreCachedFor60sAndBustedByRefresh() async {
        let s = ClaudexStore()
        var calls = 0
        s.findTool = { _ in "/bin/claudex" }
        s.runner = { _, args, _ in calls += 1; return ProcessResult(status: 0, out: "Usage\n", err: "") }
        await s.refresh()
        let first = calls
        XCTAssertEqual(first, 7) // usage, list, current, pool status, doctor, pool members, access
        await s.refresh()
        XCTAssertEqual(calls, first) // all served from the 60 s cache
        await s.refresh(fresh: true)
        XCTAssertEqual(calls, first * 2)
        XCTAssertFalse(s.usage.recognised) // "Usage" is not a table: raw text stays available for the ⚠ fallback
        XCTAssertEqual(s.usage.raw, "Usage\n")
        XCTAssertEqual(s.unrecognisedTabs, [.usage, .pool, .health])
    }

    func testMissingClaudexMakesTheMenuUnavailableUntilARetryFindsIt() async {
        let s = ClaudexStore()
        var path: String?
        var calls = 0
        s.findTool = { _ in path }
        s.runner = { _, _, _ in calls += 1; return ProcessResult(status: 0, out: "Usage\n", err: "") }
        XCTAssertEqual(s.activeTab, .usage) // not known to be missing yet
        await s.refresh()
        XCTAssertEqual(s.unavailable, "claudex not found. Install it or add it to PATH.")
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(s.visibleTabs, []) // nothing to show but why

        await s.refresh() // background callers (hover, panel open) stay quiet while it is missing
        XCTAssertEqual(calls, 0)

        path = "/bin/claudex" // installed since; Retry is a fresh refresh
        await s.refresh(fresh: true)
        XCTAssertNil(s.unavailable)
        XCTAssertEqual(calls, 7)
        XCTAssertEqual(s.visibleTabs, ClaudexTab.allCases)
        s.select(.pool)
        XCTAssertEqual(s.activeTab, .pool)
        XCTAssertEqual(s.footer, ClaudexStore.defaultFooter)
    }

    func testOutputWeDoNotRecogniseIsNotUnavailable() async {
        let s = ClaudexStore()
        s.findTool = { _ in "/bin/claudex" }
        s.runner = { _, _, _ in ProcessResult(status: 0, out: "Usage\n", err: "") }
        await s.refresh(fresh: true)
        XCTAssertNil(s.unavailable) // per-tab ⚠ handles this
    }

    func testClaudexThatCannotRunIsUnavailableWithTheReason() async {
        let s = ClaudexStore()
        s.findTool = { _ in "/bin/claudex" }
        s.runner = { _, _, _ in .failed("/bin/claudex: Permission denied") }
        await s.refresh(fresh: true)
        XCTAssertEqual(s.unavailable, "/bin/claudex: Permission denied")
    }
}
