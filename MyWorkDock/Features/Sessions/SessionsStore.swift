import Foundation
import Observation

enum SessionDateRange: String, CaseIterable, Identifiable {
    case today, yesterday, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        }
    }

    /// [from, to) in local calendar days.
    func contains(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return d >= today
        case .yesterday: return d >= today.addingTimeInterval(-86_400) && d < today
        case .week: return d >= now.addingTimeInterval(-7 * 86_400)
        case .month: return true
        }
    }
}

enum GroupFilter: Hashable {
    case all, ungrouped, group(String)
}

/// Serialises access to the transcript index off the main thread.
actor TranscriptReader {
    private let index: TranscriptIndex
    init(_ index: TranscriptIndex) { self.index = index }
    func scan() -> [Transcript] { index.scan() }
    func titles(_ ids: [String]) -> [String: String] {
        Dictionary(ids.compactMap { id in index.title(for: id).map { (id, $0) } }, uniquingKeysWith: { a, _ in a })
    }
}

/// The Sessions board: recent Claude Code sessions, grouping, filters and resume.
@MainActor @Observable
final class SessionsStore {
    static let ungroupedID = "ungrouped"

    private(set) var transcripts: [Transcript] = []
    private(set) var groups: [SessionGroup] = []
    private(set) var assignments: [String: String] = [:]
    private(set) var loading = false
    private(set) var message: (text: String, error: Bool)?
    /// Real titles for live sessions (session id → title), filled for the Agents tab.
    private(set) var titles: [String: String] = [:]
    var search = ""
    var groupFilter: GroupFilter = .all
    var range: SessionDateRange = .month
    /// Session to reveal on the board (from Agents › Show on board).
    var focusID: String?
    private(set) var installedTerminals: [OpenIn] = [.terminal]
    private(set) var openIn: OpenIn

    @ObservationIgnored private let reader: TranscriptReader?
    @ObservationIgnored private let store: SessionGroups
    @ObservationIgnored private let defaults: UserDefaults?

    init(reader: TranscriptReader?, groups: SessionGroups, defaults: UserDefaults?) {
        self.reader = reader
        self.store = groups
        self.defaults = defaults
        openIn = defaults?.string(forKey: "sessionsOpenIn").flatMap(OpenIn.init(rawValue:)) ?? .terminal
        syncGroups()
    }

    static func live() -> SessionsStore { SessionsStore(reader: TranscriptReader(TranscriptIndex()), groups: .live(), defaults: .standard) }
    static func sample() -> SessionsStore { SessionsStore(reader: nil, groups: SessionGroups(file: nil), defaults: nil) }

    func refresh() async {
        guard let reader else { return }
        loading = true
        defer { loading = false }
        transcripts = await reader.scan()
        installedTerminals = TerminalLauncher.detect()
    }

    /// Looks up titles for live sessions the board hasn't loaded yet.
    func ensureTitles(_ sessionIDs: [String]) {
        let missing = sessionIDs.filter { titles[$0] == nil }
        guard let reader, !missing.isEmpty else { return }
        Task {
            let found = await reader.titles(missing)
            titles.merge(found) { _, new in new }
        }
    }

    #if DEBUG
    func setTranscriptsForTesting(_ t: [Transcript]) { transcripts = t }

    /// Snapshots: a board with two groups.
    func loadSample() {
        func tx(_ id: String, _ title: String, _ project: String, _ branch: String?, _ hoursAgo: Double, _ tokens: Int?) -> Transcript {
            Transcript(id: id, cwd: "/w/\(project)", project: project, branch: branch, title: title,
                       lastActivity: Date().addingTimeInterval(-hoursAgo * 3600), model: "claude-opus-5-5", contextTokens: tokens, contextWindow: 200_000)
        }
        transcripts = [
            tx("s1", "Add the product schema to Strapi", "foxtale-admin", "feat/schema", 0.2, 152_000),
            tx("s2", "Fix checkout coupon rounding", "foxtale-web", "main", 3, 61_000),
            tx("s3", "Port the Sessions board to Swift", "my-work-dock", "sessions", 0.5, 98_000),
            tx("s4", "Notch island redesign", "peekaboo", "island-design", 26, 40_000),
            tx("s5", "Reminders with custom tunes", "peekaboo", "reminders", 30, nil),
        ]
        create("Foxtale")
        create("Devx tools")
        if groups.count >= 2 {
            move("s1", to: groups[0].id); move("s2", to: groups[0].id); move("s3", to: groups[1].id)
        }
        installedTerminals = [.terminal, .warp]
        message = nil
    }
    #endif

    func title(for id: String) -> String? { transcripts.first { $0.id == id }?.title ?? titles[id] }

    // MARK: Board

    func groupID(of t: Transcript) -> String { store.group(of: t.id) ?? Self.ungroupedID }

    var visible: [Transcript] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return transcripts.filter { t in
            range.contains(t.lastActivity)
                && (needle.isEmpty || [t.title, t.project, t.branch ?? ""].contains { $0.lowercased().contains(needle) })
        }
    }

    struct Column: Identifiable {
        var id: String
        var name: String
        var items: [Transcript]
        var isGroup: Bool { id != SessionsStore.ungroupedID }
    }

    var columns: [Column] {
        let v = visible
        let all = groups.map { (id: $0.id, name: $0.name) } + [(id: Self.ungroupedID, name: "Ungrouped")]
        return all.filter { c in
            switch groupFilter {
            case .all: true
            case .ungrouped: c.id == Self.ungroupedID
            case .group(let g): c.id == g
            }
        }
        .map { c in Column(id: c.id, name: c.name, items: v.filter { groupID(of: $0) == c.id }) }
    }

    /// Clears filters so `id` is visible, and marks it for the board to scroll to.
    func focus(_ id: String) {
        search = ""
        groupFilter = .all
        range = .month
        focusID = id
    }

    // MARK: Groups

    private func syncGroups() {
        groups = store.groups
        assignments = store.assignments
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work(); message = nil } catch { message = (error.localizedDescription, true) }
        syncGroups()
    }

    func create(_ name: String) { attempt { try store.create(name) } }
    func rename(_ id: String, _ name: String) { attempt { try store.rename(id, name) } }
    func delete(_ id: String) { attempt { try store.delete(id) } }

    func move(_ sessionID: String, to column: String) {
        attempt { try store.assign(sessionID, to: column == Self.ungroupedID ? nil : column) }
    }

    func autoGroup() {
        let n = store.autoGroup(transcripts.map { ($0.id, $0.project) })
        syncGroups()
        message = (n == 0 ? "Nothing to group — every session already has one." : "Grouped \(n) session\(n == 1 ? "" : "s") by project.", false)
    }

    // MARK: Resume

    func setOpenIn(_ app: OpenIn) {
        openIn = app
        defaults?.set(app.rawValue, forKey: "sessionsOpenIn")
    }

    func resume(_ t: Transcript) async {
        guard let cwd = t.cwd else { message = ("This session has no project folder recorded.", true); return }
        do {
            let used = try await TerminalLauncher.resume(cwd: cwd, id: t.id, in: openIn)
            message = used == openIn ? nil : ("\(openIn.name) didn't open, so the session opened in \(used.name).", false)
        } catch {
            message = (error.localizedDescription, true)
        }
    }

    var footer: String {
        let n = visible.count
        return "\(n) session\(n == 1 ? "" : "s") · \(groups.count) group\(groups.count == 1 ? "" : "s")"
    }
}
