import Foundation

/// Sessions, pending requests, Always rules and wake hooks. Pure logic: the socket server feeds it
/// hook messages and the UI drives decisions. Main-actor only.
@MainActor
final class AgentCore {
    enum Handled {
        case reply(HookReply)
        /// Hold the connection; `respond` is called once with the decision.
        case wait
    }

    private(set) var sessions: [String: AgentSession] = [:]
    private(set) var pending: [PendingRequest] = []
    private(set) var rules: [AlwaysRule]
    private var replies: [String: (AgentDecision) -> Void] = [:]
    private var pendingCwd: [String: String?] = [:]
    /// session id → (hook message id, reply)
    private var waiters: [String: (String, (AgentDecision) -> Void)] = [:]
    private var queued: [String: [String]] = [:]
    private var ttyTried: Set<String> = []
    /// The hook's parent of the newest message per session, for looking the terminal up again on Refresh.
    private var lastPID: [String: Int32] = [:]
    private let ttyLookup: (Int32) async -> (pid: Int32, tty: String)?
    private let isAlive: (Int32) -> Bool
    private let saveRules: ([AlwaysRule]) -> Void
    var onChange: () -> Void = {}

    static let staleAfter: TimeInterval = 30 * 60

    init(rules: [AlwaysRule] = [], ttyLookup: @escaping (Int32) async -> (pid: Int32, tty: String)? = TerminalLookup.tty,
         isAlive: @escaping (Int32) -> Bool = TerminalLookup.isAlive, saveRules: @escaping ([AlwaysRule]) -> Void = { _ in }) {
        self.rules = rules
        self.ttyLookup = ttyLookup
        self.isAlive = isAlive
        self.saveRules = saveRules
    }

    /// Live sessions, newest first.
    func liveSessions(now: Date = Date()) -> [AgentSession] {
        sessions.values
            .filter { $0.state != .ended && now.timeIntervalSince($0.updatedAt) <= Self.staleAfter }
            .map { s in var s = s; s.reachable = waiters[s.id] != nil; s.queued = queued[s.id]?.count ?? 0; return s }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func handle(_ m: HookMessage, respond: @escaping (AgentDecision) -> Void) -> Handled {
        let passthrough = HookReply.passthrough(m.id)
        guard m.v == HookWire.version, m.agent == "claude" else { return .reply(passthrough) }
        let sid = ClaudeAdapter.sessionID(m)
        let now = Date()
        if let pid = m.pid {
            lastPID[sid] = pid
            // Looked up once per session, off the main thread (it runs `ps`).
            if ttyTried.insert(sid).inserted { Task { await lookUpTerminal(sid, pid) } }
        }
        var result = Handled.reply(passthrough)
        for ev in ClaudeAdapter.events(m) {
            apply(ev, sid, m, now)
            if ev == .sessionEnded {
                waiters.removeValue(forKey: sid)?.1(.passthrough)
                queued[sid] = nil
            }
            guard m.expects_reply else { continue }
            switch ev {
            case .permission(let tool, let input):
                if rules.contains(where: { $0.matches(agent: m.agent, tool: tool, input: input, cwd: m.cwd) }) {
                    sessions[sid]?.state = .working
                    result = .reply(reply(m, .allow(always: false)))
                } else {
                    hold(m, sid, .permission(tool: tool, input: input), respond)
                    result = .wait
                }
            case .question(let qs):
                hold(m, sid, .question(qs), respond)
                result = .wait
            case .awaitingPrompt:
                if let prompts = queued.removeValue(forKey: sid), !prompts.isEmpty {
                    sessions[sid]?.state = .working
                    sessions[sid]?.lastAction = "Sent your message"
                    result = .reply(reply(m, .send(prompts.joined(separator: "\n\n"))))
                } else {
                    // One waiter per session: the previous one exits quietly.
                    waiters.updateValue((m.id, respond), forKey: sid)?.1(.passthrough)
                    result = .wait
                }
            default: break
            }
        }
        onChange()
        return result
    }

    private func hold(_ m: HookMessage, _ sid: String, _ kind: PendingKind, _ respond: @escaping (AgentDecision) -> Void) {
        pending.append(PendingRequest(id: m.id, agent: m.agent, sessionID: sid, project: projectName(m.cwd), kind: kind, createdAt: Date()))
        replies[m.id] = respond
        pendingCwd[m.id] = m.cwd
    }

    private func touch(_ sid: String, _ m: HookMessage, _ now: Date) {
        if sessions[sid] == nil {
            sessions[sid] = AgentSession(id: sid, agent: m.agent, cwd: m.cwd, project: projectName(m.cwd), state: .working, updatedAt: now)
        }
        if sessions[sid]?.cwd == nil, let cwd = m.cwd { sessions[sid]?.cwd = cwd; sessions[sid]?.project = projectName(cwd) }
        if let term = m.term { sessions[sid]?.terminal = terminalName(term) }
        sessions[sid]?.updatedAt = now
    }

    func session(_ sid: String) -> AgentSession? { sessions[sid] }

    private func lookUpTerminal(_ sid: String, _ pid: Int32) async {
        guard let found = await ttyLookup(pid) else { return }
        sessions[sid]?.tty = found.tty
        sessions[sid]?.ownerPID = found.pid
        onChange()
    }

    /// Refresh: ends sessions whose `claude` process is gone (terminal closed or killed without a SessionEnd), and looks the
    /// terminal up again for sessions that have none yet.
    func recheck() async {
        var changed = false
        for (sid, s) in sessions where s.state != .ended {
            guard let owner = s.ownerPID, !isAlive(owner) else { continue }
            sessions[sid]?.state = .ended
            waiters.removeValue(forKey: sid)?.1(.passthrough)
            queued[sid] = nil
            changed = true
        }
        if changed { onChange() }
        for (sid, s) in sessions where s.state != .ended && s.tty == nil {
            if let pid = lastPID[sid] { await lookUpTerminal(sid, pid) }
        }
    }

    private func apply(_ ev: AgentEvent, _ sid: String, _ m: HookMessage, _ now: Date) {
        touch(sid, m, now)
        func set(_ state: AgentState?, _ action: String?) {
            if let state { sessions[sid]?.state = state }
            if let action { sessions[sid]?.lastAction = action }
        }
        switch ev {
        case .sessionStarted: set(.idle, "Session started")
        case .sessionEnded: set(.ended, nil)
        case .prompt(let p): set(.working, Self.truncate(p))
        case .toolStarted(let tool, let input): set(.working, Self.summary(tool, input))
        case .toolFinished: set(.working, nil)
        case .permission(let tool, _): set(.waiting, "Needs approval: \(tool)")
        case .question: set(.waiting, "Has a question")
        case .notification(let text): set(nil, Self.truncate(text))
        case .idle: set(.idle, "Done")
        case .awaitingPrompt: break
        }
    }

    func decide(_ id: String, _ d: AgentDecision) {
        guard let i = pending.firstIndex(where: { $0.id == id }), let respond = replies.removeValue(forKey: id) else { return }
        let p = pending.remove(at: i)
        let cwd = pendingCwd.removeValue(forKey: id) ?? nil
        if case .allow(true) = d, case .permission(let tool, let input) = p.kind {
            let rule = AlwaysRule.forRequest(agent: p.agent, tool: tool, input: input, cwd: cwd)
            if !rules.contains(rule) { rules.append(rule); saveRules(rules) }
        }
        sessions[p.sessionID]?.state = .working
        respond(d)
        onChange()
    }

    /// The hook hung up (agent killed, hook timed out, or the user answered in the terminal).
    func cancel(_ id: String) {
        if let i = pending.firstIndex(where: { $0.id == id }) {
            let p = pending.remove(at: i)
            replies[id] = nil
            pendingCwd[id] = nil
            sessions[p.sessionID]?.state = .working
        }
        if let sid = waiters.first(where: { $0.value.0 == id })?.key { waiters[sid] = nil }
        onChange()
    }

    enum Delivery: Equatable { case delivered, queued }

    /// Sends a prompt: at once to an idle session with a waiting wake hook, otherwise queued for
    /// the waiter that starts when the current turn ends.
    func sendPrompt(_ sid: String, _ text: String) throws -> Delivery {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AgentError("Message is empty.") }
        guard let s = sessions[sid], s.state != .ended else { throw AgentError("That session is no longer active.") }
        if let w = waiters.removeValue(forKey: sid) {
            w.1(.send(text))
            sessions[sid]?.state = .working
            sessions[sid]?.lastAction = "Sent your message"
            onChange()
            return .delivered
        }
        if s.state == .idle {
            throw AgentError("Claude is idle in \(s.terminal ?? "its terminal") and can't be reached yet. Send one prompt there first; after that you can message it from here.")
        }
        queued[sid, default: []].append(text)
        onChange()
        return .queued
    }

    func removeRule(_ rule: AlwaysRule) {
        rules.removeAll { $0 == rule }
        saveRules(rules)
        onChange()
    }

    func reply(_ m: HookMessage, _ d: AgentDecision) -> HookReply {
        let (out, code) = ClaudeAdapter.reply(m, d)
        return HookReply(v: HookWire.version, id: m.id, stdout: out, exit_code: code)
    }

    static func truncate(_ s: String, _ max: Int = 60) -> String {
        let s = s.replacingOccurrences(of: "\n", with: " ")
        return s.count <= max ? s : String(s.prefix(max)) + "…"
    }

    static func summary(_ tool: String, _ input: JSONValue) -> String {
        for k in ["command", "file_path", "path", "pattern", "url"] {
            if let d = input[k]?.string { return truncate("\(tool): \(d)") }
        }
        return tool
    }
}

struct AgentError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
