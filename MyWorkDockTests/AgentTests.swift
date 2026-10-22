import XCTest
@testable import MyWorkDock

private func msg(_ event: String, _ payload: JSONValue, id: String = "id1", session: String? = "s", cwd: String? = "/w/shop", reply: Bool = true) -> HookMessage {
    var p = payload.object ?? [:]
    if let session { p["session_id"] = .string(session) }
    return HookMessage(v: 1, id: id, agent: "claude", event: event, cwd: cwd, pid: nil, payload: .object(p), expects_reply: reply, term: nil)
}

private func parse(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

final class HookWireTests: XCTestCase {
    func testFrameRoundTripAndLimits() throws {
        let m = msg("Stop", .object([:]))
        let frame = try HookWire.encode(m)
        let len = HookWire.length(frame.prefix(4))
        XCTAssertEqual(len, frame.count - 4)
        XCTAssertEqual(try JSONDecoder().decode(HookMessage.self, from: frame.dropFirst(4)), m)
        var big = UInt32(HookWire.maxFrame + 1).bigEndian
        XCTAssertNil(HookWire.length(Data(bytes: &big, count: 4)))
    }

    func testOlderHooksWithoutTermStillParse() throws {
        let old = #"{"v":1,"id":"a","agent":"claude","event":"Stop","payload":{},"expects_reply":false}"#
        XCTAssertNil(try JSONDecoder().decode(HookMessage.self, from: Data(old.utf8)).term)
    }
}

final class ClaudeAdapterTests: XCTestCase {
    func testNormalizes() {
        XCTAssertEqual(ClaudeAdapter.events(msg("Stop", .object([:]))), [.idle])
        XCTAssertEqual(ClaudeAdapter.events(msg("Wake", .object([:]))), [.awaitingPrompt])
        XCTAssertEqual(ClaudeAdapter.events(msg("PermissionRequest", parse(#"{"tool_name":"AskUserQuestion"}"#))), [])
        let ask = msg("PreToolUse", parse(#"{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which DB?","options":[{"label":"Postgres"},{"label":"Mongo"}],"multiSelect":false}]}}"#))
        guard case .question(let qs) = ClaudeAdapter.events(ask).first else { return XCTFail() }
        XCTAssertEqual(qs.first?.options.map(\.label), ["Postgres", "Mongo"])
        XCTAssertEqual(ClaudeAdapter.sessionID(msg("Stop", .object([:]), session: "abc")), "claude:abc")
    }

    func testRendersPermissionAnswersAndWake() {
        let perm = msg("PermissionRequest", .object([:]))
        let (allow, code) = ClaudeAdapter.reply(perm, .allow(always: false))
        XCTAssertEqual(code, 0)
        XCTAssertEqual(parse(allow)["hookSpecificOutput"]?["decision"]?["behavior"], .string("allow"))
        XCTAssertEqual(parse(ClaudeAdapter.reply(perm, .deny(reason: nil)).0)["hookSpecificOutput"]?["decision"]?["message"], .string("Denied from MyWorkDock"))

        let ask = msg("PreToolUse", parse(#"{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which DB?"}]}}"#))
        let out = parse(ClaudeAdapter.reply(ask, .answer([QuestionAnswer(question: "Which DB?", answer: "Mongo")])).0)["hookSpecificOutput"]
        XCTAssertEqual(out?["permissionDecision"], .string("allow"))
        XCTAssertEqual(out?["updatedInput"]?["answers"]?["Which DB?"], .string("Mongo"))
        XCTAssertNotNil(out?["updatedInput"]?["questions"], "original input is kept")

        let (wake, wcode) = ClaudeAdapter.reply(msg("Wake", .object([:])), .send("add tests"))
        XCTAssertEqual(wcode, 2, "exit 2 wakes Claude")
        XCTAssertTrue(wake.contains("add tests"))
        XCTAssertEqual(ClaudeAdapter.reply(perm, .passthrough).0, "")
    }
}

@MainActor
final class AgentCoreTests: XCTestCase {
    private func core() -> AgentCore { AgentCore(ttyLookup: { _ in nil }) }
    private func perm(_ id: String, _ session: String, tool: String = "Bash", cmd: String = "ls", cwd: String = "/w/shop") -> HookMessage {
        msg("PermissionRequest", .object(["tool_name": .string(tool), "tool_input": .object(["command": .string(cmd)])]), id: id, session: session, cwd: cwd)
    }

    func testPermissionWaitsAndDecideReplies() {
        let c = core()
        var got: AgentDecision?
        guard case .wait = c.handle(perm("1", "s"), respond: { got = $0 }) else { return XCTFail("held") }
        XCTAssertEqual(c.pending.count, 1)
        XCTAssertEqual(c.liveSessions().first?.state, .waiting)
        c.decide("1", .allow(always: false))
        XCTAssertEqual(got, .allow(always: false))
        XCTAssertTrue(c.pending.isEmpty)
        XCTAssertEqual(c.liveSessions().first?.state, .working)
    }

    func testTwoRequestsResolveIndependently() {
        let c = core()
        var a: AgentDecision?, b: AgentDecision?
        _ = c.handle(perm("1", "s1"), respond: { a = $0 })
        _ = c.handle(perm("2", "s2"), respond: { b = $0 })
        c.decide("2", .deny(reason: nil))
        XCTAssertNil(a)
        XCTAssertEqual(b, .deny(reason: nil))
        XCTAssertEqual(c.pending.map(\.id), ["1"])
    }

    func testAlwaysIsScopedToProjectAndExactCommand() {
        var saved: [AlwaysRule] = []
        let c = AgentCore(ttyLookup: { _ in nil }, saveRules: { saved = $0 })
        _ = c.handle(perm("1", "s", cmd: "npm test"), respond: { _ in })
        c.decide("1", .allow(always: true))
        XCTAssertEqual(saved, [AlwaysRule(agent: "claude", tool: "Bash", cwd: "/w/shop", command: "npm test")])
        guard case .reply(let r) = c.handle(perm("2", "s", cmd: "npm test"), respond: { _ in }) else { return XCTFail("auto-allowed") }
        XCTAssertTrue(r.stdout.contains("allow"))
        guard case .wait = c.handle(perm("3", "s", cmd: "rm -rf ~"), respond: { _ in }) else { return XCTFail("other command asks") }
        guard case .wait = c.handle(perm("4", "s", cmd: "npm test", cwd: "/w/other"), respond: { _ in }) else { return XCTFail("other project asks") }
    }

    func testCancelClearsPending() {
        let c = core()
        _ = c.handle(perm("1", "s"), respond: { _ in })
        c.cancel("1")
        XCTAssertTrue(c.pending.isEmpty)
        XCTAssertEqual(c.liveSessions().first?.state, .working)
    }

    func testWakeHookDeliversPromptsToIdleSessions() throws {
        let c = core()
        _ = c.handle(msg("Stop", .object([:]), id: "stop", reply: false), respond: { _ in })
        XCTAssertThrowsError(try c.sendPrompt("claude:s", "hi"), "idle with no waiter")
        var got: AgentDecision?
        guard case .wait = c.handle(msg("Wake", .object([:]), id: "w1"), respond: { got = $0 }) else { return XCTFail() }
        XCTAssertTrue(c.liveSessions().first!.reachable)
        XCTAssertEqual(try c.sendPrompt("claude:s", "next: docs"), .delivered)
        XCTAssertEqual(got, .send("next: docs"))
        XCTAssertFalse(c.liveSessions().first!.reachable)
    }

    func testPromptWhileWorkingGoesOutWithTheNextWaiter() throws {
        let c = core()
        _ = c.handle(msg("UserPromptSubmit", .object(["prompt": .string("go")]), id: "p", reply: false), respond: { _ in })
        XCTAssertEqual(try c.sendPrompt("claude:s", "then docs"), .queued)
        XCTAssertEqual(c.liveSessions().first?.queued, 1)
        guard case .reply(let r) = c.handle(msg("Wake", .object([:]), id: "w1"), respond: { _ in }) else { return XCTFail() }
        XCTAssertEqual(r.exit_code, 2)
        XCTAssertTrue(r.stdout.contains("then docs"))
    }

    func testNewerWaiterReplacesOldAndSessionEndReleasesIt() {
        let c = core()
        var old: AgentDecision?, newer: AgentDecision?
        _ = c.handle(msg("Wake", .object([:]), id: "w1"), respond: { old = $0 })
        _ = c.handle(msg("Wake", .object([:]), id: "w2"), respond: { newer = $0 })
        XCTAssertEqual(old, .passthrough)
        _ = c.handle(msg("SessionEnd", .object([:]), id: "e", reply: false), respond: { _ in })
        XCTAssertEqual(newer, .passthrough)
        XCTAssertTrue(c.liveSessions().isEmpty)
    }

    func testRecordsTerminalApp() {
        let c = core()
        var m = msg("Stop", .object([:]), reply: false)
        m.term = "WarpTerminal"
        _ = c.handle(m, respond: { _ in })
        XCTAssertEqual(c.liveSessions().first?.terminal, "Warp")
        XCTAssertFalse(c.liveSessions().first!.canTypeInto)
    }

    func testTTYIsLookedUpOnceInTheBackground() async {
        var lookups = 0
        let c = AgentCore(ttyLookup: { _ in lookups += 1; return "ttys004" })
        var m = msg("Stop", .object([:]), reply: false)
        m.pid = 42
        _ = c.handle(m, respond: { _ in })
        _ = c.handle(m, respond: { _ in })
        for _ in 0..<50 where c.liveSessions().first?.tty == nil { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(c.liveSessions().first?.tty, "ttys004")
        XCTAssertEqual(lookups, 1)
    }
}

final class TerminalLookupTests: XCTestCase {
    func testWalksPastDetachedHookShell() {
        let table: [Int32: (Int32, String?)] = [30: (20, nil), 20: (10, "ttys002")]
        XCTAssertEqual(TerminalLookup.walk(30) { table[$0] }, "ttys002")
        XCTAssertNil(TerminalLookup.walk(99) { table[$0] })
        XCTAssertNil(TerminalLookup.walk(5) { _ in (5, nil) }, "stops on cycles")
        let parsed = TerminalLookup.parsePS("  30    20 ??\n  20    10 ttys002\n")
        XCTAssertEqual(parsed[20]?.1, "ttys002")
        XCTAssertNil(parsed[30]?.1)
    }

    func testTypingScriptsTargetTheTabAndNeverLaunchApps() {
        let s = TerminalLookup.typingScripts(tty: "ttys004", text: "fix \"it\" \\ now\nplease", iterm: true)
        XCTAssertEqual(s.count, 2)
        XCTAssertTrue(s[0].hasPrefix("if application \"Terminal\" is running then"))
        XCTAssertTrue(s[0].contains("tty of tb is \"/dev/ttys004\""))
        XCTAssertTrue(s[0].contains(#"do script "fix \"it\" \\ now please" in tb"#), s[0])
        XCTAssertTrue(TerminalLookup.typingScripts(tty: "ttys0\" & do shell script \"x", text: "hi", iterm: false).isEmpty)
    }
}
