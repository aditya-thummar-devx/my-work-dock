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

    var waitingCount: Int { pending.count }

    var footer: String {
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
        if let installer, installer.status().installed { try? installer.deployHook() }
        refreshHooks()
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

    func refreshHooks() {
        guard let installer else { return }
        hooks = installer.status()
    }

    func decide(_ id: String, _ d: AgentDecision) { core.decide(id, d) }

    func removeRule(_ r: AlwaysRule) { core.removeRule(r) }

    /// One click sets messaging up for every session (installs or repairs the Claude hooks).
    func installHooks() {
        guard let installer, !installing else { return }
        installing = true
        defer { installing = false }
        do { try installer.install() } catch { serverError = error.localizedDescription }
        refreshHooks()
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
