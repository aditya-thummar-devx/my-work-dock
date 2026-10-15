import Foundation
import Observation

enum ClaudexTab: String, CaseIterable { case usage, pool, play, health }

/// One claudex read: what the parser made of it, and the raw text it came from, so a panel can fall back to
/// plain text (with a ⚠) when the parser no longer recognises the output.
struct Capture<T> {
    var data: T?
    var raw = ""
    var error: String?
    var recognised: Bool { data != nil }

    static var empty: Capture { Capture() }
}

struct PlayLine: Identifiable, Equatable {
    enum Kind { case cmd, ok, warn, text }
    let id = UUID()
    var text: String
    var kind: Kind = .text
}

struct PlayCommand: Identifiable {
    var id: String
    var title: String
    var desc: String
    var chips: [Chip] = []
    /// nil for expandable commands.
    var run: (() -> Void)?
    var expandable: Bool { run == nil }

    struct Chip: Identifiable {
        var label: String
        var danger = false
        var run: () -> Void
        var id: String { label }
    }
}

/// claudex through its CLI. Reads are cached for 60 s (Refresh and every write bust the cache), every write
/// goes through the `Confirmer` first, and parsers return nil on unknown output. `live == false` (snapshots,
/// tests) never launches a process.
@MainActor @Observable
final class ClaudexStore {
    // View state
    var tab: ClaudexTab = .usage
    var maxOnly = false
    var sort: ClaudexSort = .resetAsc
    var sortOpen = false
    private(set) var expanded: Set<String> = []
    private(set) var out: [PlayLine] = []
    private(set) var message: String?
    var rawOn = false

    // Data
    private(set) var usage = Capture<[UsageRow]>.empty
    private(set) var list = Capture<[AccountRow]>.empty
    private(set) var current = Capture<CurrentAccount>.empty
    private(set) var poolStatus = Capture<PoolStatus>.empty
    private(set) var doctor = Capture<Doctor>.empty
    private(set) var members = Capture<[PoolMember]>.empty
    private(set) var access = Capture<[AccessPerson]>.empty
    private(set) var me: (account: String, pool: String?)?
    private(set) var fetchedAt: Date?
    private(set) var loading = false
    /// The pool member a confirmed write is running for (until the refresh after it lands).
    private(set) var busyMember: String?

    // Member details sheet
    private(set) var detailName: String?
    private(set) var detail = Capture<MemberDetail>.empty
    private(set) var detailAge = 0
    private(set) var detailLoading = false

    let confirmer: Confirmer
    @ObservationIgnored let live: Bool
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored var runner: @Sendable (String, [String], TimeInterval) async -> ProcessResult = { await ProcessRunner.run($0, $1, timeout: $2) }
    @ObservationIgnored var findTool: @Sendable (String) async -> String? = { await PathResolver.find($0) }
    @ObservationIgnored var identityURL = URL(fileURLWithPath: NSHomeDirectory() + "/.claude-accounts/identity.json")
    @ObservationIgnored private var cache: [String: (raw: String, at: Date)] = [:]
    /// Called after every refresh; the peek reads its data from here.
    @ObservationIgnored var onData: (() -> Void)?

    static let readTimeout: TimeInterval = 10
    static let writeTimeout: TimeInterval = 30
    static let ttl: TimeInterval = 60
    static let defaultFooter = "Reads cached 60s · writes ask first"

    init(confirmer: Confirmer? = nil) {
        self.confirmer = confirmer ?? Confirmer()
        live = true
    }

    /// The designs' sample content (Prototype `cxData()` at its default state).
    init(sample: Bool, confirmer: Confirmer? = nil) {
        self.confirmer = confirmer ?? Confirmer()
        live = false
        let fixed = SampleData.now
        now = { fixed }
        usage = Capture(data: SampleData.usageRows)
        members = Capture(data: SampleData.poolMembers)
        poolStatus = Capture(data: SampleData.poolStatus)
        doctor = Capture(data: SampleData.doctor)
        access = Capture(data: SampleData.access)
        list = Capture(data: SampleData.usageRows.map { AccountRow(account: $0.account, active: $0.active, email: "", org: "", plan: $0.tier, saved: "") })
        current = Capture(data: CurrentAccount(account: "work", email: "", org: "", plan: ""))
        me = SampleData.me
        fetchedAt = fixed
    }

    // MARK: Derived

    private func is5x(_ plan: String) -> Bool { plan.range(of: "5x", options: .caseInsensitive) != nil }

    private func reading(_ g: Gauge) -> Reading? { g.pct.map { Reading(percent: $0, reset: g.at ?? "") } }

    private func key(name: String, session: Gauge, week: Gauge) -> ClaudexSort.Key {
        ClaudexSort.Key(name: name, session: session.pct, week: week.pct, reset: ClaudexSort.resetAt(week.at, now: now()))
    }

    /// Usage cards: filtered by "5x only", then sorted.
    var accountCards: [AccountSample] {
        let rows = (usage.data ?? []).filter { !maxOnly || is5x($0.tier) }
        return sort.apply(rows) { key(name: $0.account, session: $0.session, week: $0.week) }.map {
            AccountSample(id: $0.account, plan: $0.tier, session: reading($0.session), week: reading($0.week), active: $0.active)
        }
    }

    /// The pool member claudex marks as serving you; none means you are on your own token.
    var usingName: String? { members.data?.first { $0.marked }?.name ?? me?.pool }

    var memberCards: [MemberSample] {
        let rows = (members.data ?? []).filter { !maxOnly || is5x($0.plan) }
        return sort.apply(rows) { key(name: $0.name, session: $0.session, week: $0.week) }.map { m in
            MemberSample(id: m.name, plan: m.plan, net: m.netM ?? 0, session: reading(m.session), week: reading(m.week),
                         using: usingName == m.name, denied: access.data?.first { $0.name == m.name }?.allowed == false,
                         mine: me?.pool == m.name, busy: busyMember == m.name)
        }
    }

    var accountNames: [String] { (list.data?.map(\.account) ?? usage.data?.map(\.account) ?? []) }

    /// "Switch to mine" (claudex-dash mine.js): which command, if any, puts you back on your own account here.
    var mineCommand: [String]? {
        guard let me else { return nil }
        switch tab {
        case .pool:
            guard let pool = me.pool, members.recognised else { return nil }
            return members.data?.first { $0.marked }?.name == pool ? nil : ["pool", "use", pool]
        case .usage:
            guard current.recognised else { return nil }
            return current.data?.account == me.account ? nil : ["switch", me.account, "--force"]
        default: return nil
        }
    }

    var consuming: Bool? { poolStatus.data?.consuming.on }
    /// doctor prints exactly "disabled" when autoswitch is off.
    var autoswitchOn: Bool? { doctor.data?.checks.first { $0.label == "autoswitch" }.map { $0.detail != "disabled" } }

    var unrecognisedTabs: Set<ClaudexTab> {
        var s: Set<ClaudexTab> = []
        if live, !usage.recognised || !list.recognised || !current.recognised { s.insert(.usage) }
        if live, !members.recognised || !access.recognised { s.insert(.pool) }
        if live, !doctor.recognised || !poolStatus.recognised { s.insert(.health) }
        return s
    }

    var footer: String { message ?? Self.defaultFooter }

    /// Peek ears: pool on -> the pool member claudex has selected (▶, POOL); pool off -> the active account of the SSO
    /// list (SSO). No reading shows "—" and "no reading". nil when claudex gave no account at all (missing, logged out, unreadable).
    private var livePeek: PeekData? {
        if consuming == true, let m = members.data?.first(where: \.marked) {
            return PeekData(name: m.name, isPool: true, bars: Self.peekBars(m.session, m.week))
        }
        if let row = usage.data?.first(where: \.active) {
            return PeekData(name: row.account, isPool: false, bars: Self.peekBars(row.session, row.week))
        }
        return current.data.map { PeekData(name: $0.account, isPool: false, bars: Self.peekBars(.none, .none)) }
    }

    var peekData: PeekData { livePeek ?? PeekData(name: "claudex", isPool: false, bars: Self.peekBars(.none, .none)) }

    private static func peekBars(_ session: Gauge, _ week: Gauge) -> [PeekBar] {
        // The week's reset shows as a date ("Oct 19"), the session's as claudex printed it.
        let day = week.at.map { $0.split(separator: " ").prefix(2).joined(separator: " ") }
        return [PeekBar(label: "5H", percent: session.pct, reset: session.at), PeekBar(label: "WEEK", percent: week.pct, reset: day)]
    }

    /// Hover has an account to show; false while claudex is missing or has not answered yet.
    var hasPeek: Bool { livePeek != nil }

    var freshLabel: String {
        guard let fetchedAt else { return "not loaded" }
        let age = Int(now().timeIntervalSince(fetchedAt))
        return age < 5 ? "just now" : age < 60 ? "\(age)s ago" : "\(age / 60)m ago"
    }

    /// Health tab rows: the doctor checks, plus any account that is not healthy.
    var healthChecks: [DoctorCheck] { (doctor.data?.checks ?? []) + (doctor.data?.accounts.filter { !$0.ok } ?? []) }
    var healthCounts: (ok: Int, warn: Int) {
        let all = (doctor.data?.checks ?? []) + (doctor.data?.accounts ?? [])
        return (all.filter(\.ok).count, all.filter { !$0.ok }.count)
    }

    var detailMeta: String {
        guard let d = detail.data else { return "" }
        return "\(d.plan) · \(d.sharing ? "sharing" : "not sharing") · \(d.state)"
    }

    // MARK: Reading

    private func claudex(_ args: [String], timeout: TimeInterval) async -> ProcessResult {
        guard let exe = await findTool("claudex") else { return .failed("claudex not found. Install it or add it to PATH.") }
        return await runner(exe, args, timeout)
    }

    /// claudex prints its error pages to stdout or stderr, so both are kept and the parser decides.
    private func capture(_ args: [String], fresh: Bool) async -> (raw: String, age: Int, error: String?) {
        let key = args.joined(separator: " ")
        let t = now()
        if !fresh, let hit = cache[key], t.timeIntervalSince(hit.at) < Self.ttl { return (hit.raw, Int(t.timeIntervalSince(hit.at)), nil) }
        let r = await claudex(args, timeout: Self.readTimeout)
        if r.status == -1 || r.timedOut {
            // Serve stale rather than nothing, and say so.
            if let hit = cache[key] { return (hit.raw, Int(t.timeIntervalSince(hit.at)), "stale: " + (r.timedOut ? "timed out" : r.err)) }
            return ("", 0, r.timedOut ? "timed out after \(Int(Self.readTimeout))s" : r.err)
        }
        let raw = r.out + r.err
        cache[key] = (raw, t)
        return (raw, 0, nil)
    }

    private func parsed<T>(_ args: [String], fresh: Bool, _ parse: (String) -> T?) async -> Capture<T> {
        let c = await capture(args, fresh: fresh)
        return Capture(data: parse(c.raw), raw: c.raw, error: c.error)
    }

    func refresh(fresh: Bool = false) async {
        guard live, !loading else { return }
        loading = true
        defer { loading = false }
        async let u = parsed(["usage"], fresh: fresh, ClaudexParsers.usage)
        async let l = parsed(["list"], fresh: fresh, ClaudexParsers.list)
        async let c = parsed(["current"], fresh: fresh, ClaudexParsers.current)
        async let ps = parsed(["pool", "status"], fresh: fresh, ClaudexParsers.poolStatus)
        async let d = parsed(["doctor"], fresh: fresh, ClaudexParsers.doctor)
        async let m = parsed(["pool", "members"], fresh: fresh, ClaudexParsers.poolMembers)
        async let a = parsed(["access"], fresh: fresh, ClaudexParsers.access)
        (usage, list, current, poolStatus, doctor, members, access) = await (u, l, c, ps, d, m, a)
        me = resolveMe()
        fetchedAt = now()
        onData?()
    }

    /// Refresh button: bust the cache and read everything again.
    func refreshNow() {
        guard live else { return }
        Task {
            await refresh(fresh: true)
            message = "Refreshed · fresh capture"
        }
    }

    /// Which account is mine: ~/.claude-accounts/identity.json (survives every `switch`; `current` does not).
    private func resolveMe() -> (account: String, pool: String?)? {
        guard let data = try? Data(contentsOf: identityURL),
              let email = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["email"] as? String else { return nil }
        let who = email.lowercased()
        let local: (String) -> String = { $0.split(separator: "@").first.map(String.init)?.lowercased() ?? "" }
        guard let a = list.data?.first(where: { $0.account.lowercased() == who || $0.email.lowercased() == who || local($0.email) == who })
        else { return nil }
        let pool = local(a.email)
        return (a.account, members.data?.contains { $0.name == pool } == true ? pool : nil)
    }

    // MARK: Navigation

    func select(_ t: ClaudexTab) {
        tab = t
        sortOpen = false
        detailName = nil
        detailLoading = false
    }

    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func clearOutput() { out = [] }

    // MARK: Member details

    func openDetail(_ name: String) {
        guard members.data?.contains(where: { $0.name == name }) == true else { return } // names come from claudex's own list only
        detailName = name
        sortOpen = false
        rawOn = false
        guard live else { return }
        detail = .empty
        Task { await loadDetail(fresh: false) }
    }

    func refreshDetail() {
        guard live else { return }
        Task { await loadDetail(fresh: true) }
    }

    func closeDetail() {
        detailName = nil
        detailLoading = false
        rawOn = false
    }

    private func loadDetail(fresh: Bool) async {
        guard let name = detailName else { return }
        detailLoading = true
        let c = await capture(["pool", "member", name], fresh: fresh)
        guard detailName == name else { return }
        detail = Capture(data: ClaudexParsers.memberDetail(c.raw), raw: c.raw, error: c.error)
        detailAge = c.age
        detailLoading = false
    }

    var detailFresh: String { detailAge == 0 ? "refreshed just now" : "cached · \(detailAge)s" }

    // MARK: Writes (all behind the confirm sheet)

    private func display(_ args: [String]) -> String { (["claudex"] + args).joined(separator: " ") }

    /// `member` names the pool member whose card shows a spinner until the write and the refresh after it finish.
    private func ask(_ title: String, _ args: [String], note: String, ok: String, danger: Bool = false, member: String? = nil) {
        let command = display(args)
        confirmer.ask(ConfirmRequest(title: title, command: command, note: note, confirmTitle: ok, danger: danger) { [weak self] in
            guard let self else { return }
            busyMember = member
            defer { busyMember = nil }
            let r = await claudex(args, timeout: Self.writeTimeout)
            cache.removeAll() // everything cached describes the pre-change world
            out += [PlayLine(text: "$ \(command)", kind: .cmd)]
            if r.ok {
                message = "Ran: \(command)"
                out += [PlayLine(text: "✓ done", kind: .ok)]
            } else {
                let why = r.timedOut ? "timed out after \(Int(Self.writeTimeout))s" : (r.firstLine.isEmpty ? "exit \(r.status)" : r.firstLine)
                message = "Failed: \(command) · \(why)"
                out += [PlayLine(text: "⚠ \(why)", kind: .warn)]
            }
            await refresh(fresh: true)
        })
    }

    func switchAccount(_ name: String) {
        guard accountNames.contains(name) else { return }
        ask("Switch this Mac to \(name)?", ["switch", name, "--force"], note: "Sessions started after this use it.", ok: "Switch")
    }

    func removeAccount(_ name: String) {
        guard accountNames.contains(name) else { return }
        ask("Remove \(name)?", ["remove", name, "--force"], note: "Permanently deletes the saved token. Cannot be undone.", ok: "Remove", danger: true)
    }

    func useMember(_ name: String) {
        guard members.data?.contains(where: { $0.name == name }) == true else { return }
        if name == me?.pool {
            ask("Switch back to your own account?", ["pool", "use", name], note: "Usage counts against your own limit again.", ok: "Switch", member: name)
        } else {
            ask("Use \(name)’s account?", ["pool", "use", name], note: "Your usage counts against their limit.", ok: "Switch", member: name)
        }
    }

    func switchToMine() {
        guard let args = mineCommand else { return }
        if args[0] == "switch" {
            ask("Switch back to your own account?", args, note: "Sessions started after this use it.", ok: "Switch")
        } else {
            ask("Switch back to your own account?", args, note: "Usage counts against your own limit again.", ok: "Switch")
        }
    }

    func toggleAccess(_ name: String) {
        guard let person = access.data?.first(where: { $0.name == name }) else {
            message = "\(name) is not on your access list"
            return
        }
        if person.allowed {
            ask("Deny \(name)?", ["access", "deny", name], note: "If they are using your token right now, this cuts them off immediately.", ok: "Deny", danger: true, member: name)
        } else {
            ask("Allow \(name)?", ["access", "allow", name], note: "They can borrow your account through the pool again.", ok: "Allow", member: name)
        }
    }

    func togglePool(on: Bool? = nil) {
        let start = on ?? !(consuming ?? false)
        if start {
            ask("Start the pool?", ["pool", "start"], note: "Requests fail over across pool accounts.", ok: "Start")
        } else {
            ask("Stop the pool?", ["pool", "stop"], note: "You go back to your own account only.", ok: "Stop")
        }
    }

    func toggleAutoswitch(on: Bool? = nil) {
        let enable = on ?? !(autoswitchOn ?? false)
        if enable {
            ask("Enable autoswitch?", ["autoswitch", "on"], note: "claudex switches account when usage gets high.", ok: "Enable")
        } else {
            ask("Disable autoswitch?", ["autoswitch", "off"], note: "You stay on the current account at the limit.", ok: "Disable")
        }
    }

    // MARK: Playground

    private func play(_ alias: String, _ args: [String]) {
        Task {
            let c = await capture(args, fresh: false)
            var lines = [PlayLine(text: "$ claudex \(alias)", kind: .cmd)]
            let text = c.error != nil && c.raw.isEmpty ? "⚠ \(c.error ?? "")" : c.raw
            for l in ClaudexParsers.lines(text).map({ $0.replacing(/\s+$/, with: "") }) where !l.isEmpty {
                let t = l.trimmingCharacters(in: .whitespaces)
                lines.append(PlayLine(text: l, kind: t.hasPrefix("✓") ? .ok : (t.hasPrefix("✗") || t.hasPrefix("⚠") ? .warn : .text)))
            }
            out += lines
        }
    }

    var commands: [PlayCommand] {
        let names = accountNames
        return [
            PlayCommand(id: "usage", title: "Usage", desc: "Rate-limit usage across your saved accounts: session and weekly gauges.", run: { [self] in play("usage", ["usage"]) }),
            PlayCommand(id: "ls", title: "List accounts", desc: "List saved accounts (alias: ls).", run: { [self] in play("ls", ["list"]) }),
            PlayCommand(id: "whoami", title: "Current account", desc: "Show the currently active account (alias: whoami).", run: { [self] in play("whoami", ["current"]) }),
            PlayCommand(id: "doctor", title: "Doctor", desc: "Health-check your claudex setup: what’s on, wired, or failing.", run: { [self] in play("doctor", ["doctor"]) }),
            PlayCommand(id: "switch", title: "Switch → name", desc: "Log this Mac into a saved account. Sessions started after this use it.",
                        chips: names.map { n in .init(label: n) { [self] in switchAccount(n) } }),
            PlayCommand(id: "remove", title: "Remove → name", desc: "Permanently delete a saved profile’s token. Cannot be undone.",
                        chips: names.map { n in .init(label: n, danger: true) { [self] in removeAccount(n) } }),
            PlayCommand(id: "pool", title: "Pool", desc: "Pool accounts behind one auto-failover proxy.",
                        chips: [.init(label: "status") { [self] in play("pool status", ["pool", "status"]) },
                                .init(label: "start") { [self] in togglePool(on: true) },
                                .init(label: "stop") { [self] in togglePool(on: false) }]),
            PlayCommand(id: "access", title: "Access", desc: "Who may borrow your account through the pool.",
                        chips: [.init(label: "list") { [self] in play("access list", ["access"]) }]),
            PlayCommand(id: "autoswitch", title: "Autoswitch", desc: "Auto-switch accounts when usage gets high.",
                        chips: [.init(label: "status") { [self] in play("autoswitch status", ["autoswitch", "status"]) },
                                .init(label: "on") { [self] in toggleAutoswitch(on: true) },
                                .init(label: "off") { [self] in toggleAutoswitch(on: false) }]),
        ]
    }

    // MARK: Snapshot helpers

    /// Snapshot states only.
    func showSampleDetail() {
        detailName = SampleData.memberDetail.name
        detail = Capture(data: SampleData.memberDetail, raw: SampleData.memberDetailRaw)
        detailAge = 60
    }

    func showSampleOutput() {
        out = SampleData.playgroundOutput
        expanded = ["pool"]
    }
}
