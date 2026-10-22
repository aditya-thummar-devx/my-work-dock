import Foundation
import Observation

/// What the Agents tab shows and does: live sessions, pending requests, Claude hook setup, and
/// messaging sessions. Wraps `AgentCore` and its socket server.
@MainActor @Observable
final class AgentStore {
    private(set) var sessions: [AgentSession] = []
    private(set) var pending: [PendingRequest] = []
    private(set) var rules: [AlwaysRule] = []
    private(set) var hooks = ClaudeHookInstaller.Status(installed: false, stale: false)
    private(set) var serverError: String?
    /// Per-session result of the last message ("Typed into Terminal", an error, …).
    private(set) var notes: [String: (text: String, error: Bool)] = [:]
    private(set) var sending: Set<String> = []
    private(set) var installing = false
    /// False until the hook setup has been read once: the tab shows a loading state until then.
    private(set) var checked = false

    @ObservationIgnored private let core: AgentCore
    @ObservationIgnored private var server: AgentServer?
    @ObservationIgnored private let installer: ClaudeHookInstaller?
    @ObservationIgnored private let live: Bool
    /// Called after every change (the shell uses it for the waiting count).
    @ObservationIgnored var onData: () -> Void = {}

    private static let rulesKey = "agentAlwaysRules"

    init(core: AgentCore, installer: ClaudeHookInstaller?, live: Bool) {
        self.core = core
        self.installer = installer
        self.live = live
        core.onChange = { [weak self] in self?.sync() }
        sync()
    }

    static func live() -> AgentStore {
        let saved = UserDefaults.standard.data(forKey: rulesKey).flatMap { try? JSONDecoder().decode([AlwaysRule].self, from: $0) } ?? []
        let core = AgentCore(rules: saved, saveRules: { rules in
            UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: rulesKey)
        })
        return AgentStore(core: core, installer: .live(), live: true)
    }

    /// Designs / snapshots: no server, no files.
    static func sample() -> AgentStore { AgentStore(core: AgentCore(ttyLookup: { _ in nil }), installer: nil, live: false) }

    #if DEBUG
    /// Snapshots: a few live sessions, a permission request and a question.
    func loadSample() {
        func m(_ event: String, _ session: String, _ cwd: String, _ payload: [String: JSONValue], id: String = UUID().uuidString, reply: Bool = false, term: String? = nil) -> HookMessage {
            var p = payload
            p["session_id"] = .string(session)
            return HookMessage(v: 1, id: id, agent: "claude", event: event, cwd: cwd, pid: nil, payload: .object(p), expects_reply: reply, term: term)
        }
        _ = core.handle(m("UserPromptSubmit", "a1", "/w/foxtale-admin", ["prompt": .string("Add the product schema")], term: "WarpTerminal")) { _ in }
        _ = core.handle(m("PreToolUse", "a1", "/w/foxtale-admin", ["tool_name": .string("Bash"), "tool_input": .object(["command": .string("npm run build")])])) { _ in }
        _ = core.handle(m("Stop", "b2", "/w/peekaboo", [:], term: "Apple_Terminal")) { _ in }
        _ = core.handle(m("PermissionRequest", "a1", "/w/foxtale-admin", ["tool_name": .string("Bash"),
                                                                          "tool_input": .object(["command": .string("rm -rf dist && npm run build")])], id: "p1", reply: true)) { _ in }
        _ = core.handle(m("PreToolUse", "c3", "/w/my-work-dock", ["tool_name": .string("AskUserQuestion"), "tool_input": .object(["questions": .array([
            .object(["question": .string("Which database should the sessions board use?"), "multiSelect": .bool(false),
                     "options": .array([.object(["label": .string("SQLite")]), .object(["label": .string("JSON files")]), .object(["label": .string("Core Data")])])])
        ])])], id: "q1", reply: true)) { _ in }
        hooks = .init(installed: true, stale: false)
        checked = true
    }

    /// Snapshots: set up, nothing running.
    func showSampleEmpty() {
        hooks = .init(installed: true, stale: false)
        checked = true
    }
    #endif

    var waitingCount: Int { pending.count }

    var footer: String {
        guard checked else { return "Connecting to Claude Code…" }
        let n = sessions.count, w = pending.count
        let live = n == 1 ? "1 live session" : "\(n) live sessions"
        return w > 0 ? "\(live) · \(w) waiting for you" : live
    }

    func start() {
        guard live, server == nil else { return }
        let s = AgentServer(core: core)
        do {
            try s.start()
            server = s
            serverError = nil
        } catch {
            serverError = error.localizedDescription
        }
        // Keep the stable hook copy current (app updates, moved bundles) once the user has set it up.
        Task { await refreshHooks(deploy: true) }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private func sync() {
        sessions = core.liveSessions()
        pending = core.pending
        rules = core.rules
        onData()
    }

    /// Refresh: the hook setup, then drops sessions whose `claude` has gone and finds missing terminals.
    func refresh() async {
        await refreshHooks()
        await core.recheck()
    }

    /// Reads the hook setup off the main thread. `deploy` also keeps the stable hook copy current (app updates, moved bundles) once
    /// the user has set it up.
    func refreshHooks(deploy: Bool = false) async {
        guard let installer else { checked = true; return }
        hooks = await Task.detached {
            if deploy, installer.status().installed { try? installer.deployHook() }
            return installer.status()
        }.value
        checked = true
    }

    func decide(_ id: String, _ d: AgentDecision) { core.decide(id, d) }

    func removeRule(_ r: AlwaysRule) { core.removeRule(r) }

    /// One click sets messaging up for every session (installs or repairs the Claude hooks).
    func installHooks() {
        guard let installer, !installing else { return }
        installing = true
        defer { installing = false }
        do { try installer.install() } catch { serverError = error.localizedDescription }
        hooks = installer.status()
    }

    /// Typed into the session's terminal when it allows it (a real prompt), otherwise delivered
    /// through the wake hook or queued for the end of the current turn.
    func send(_ sessionID: String, _ text: String) async {
        guard let s = core.session(sessionID), !sending.contains(sessionID) else { return }
        sending.insert(sessionID)
        defer { sending.remove(sessionID) }
        do {
            if s.canTypeInto, let tty = s.tty, try await TerminalLookup.type(tty: tty, text: text) {
                notes[sessionID] = ("Typed into \(s.terminal ?? "Terminal")", false)
                return
            }
            switch try core.sendPrompt(sessionID, text) {
            case .delivered: notes[sessionID] = ("Sent — Claude is working on it", false)
            case .queued: notes[sessionID] = ("Queued — sent when Claude finishes this turn", false)
            }
        } catch {
            notes[sessionID] = (error.localizedDescription, true)
        }
    }
}
