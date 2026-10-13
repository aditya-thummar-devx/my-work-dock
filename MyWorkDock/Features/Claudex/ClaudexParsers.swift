import Foundation

// Parsers for `claudex` CLI output, ported from claudex-dash (src/parse.ts).
//
// claudex has no --json flag and self-updates, so its printed text is the only contract. Every parser
// returns nil on a shape it does not recognise rather than inventing rows; the UI then shows the raw text
// with a ⚠ instead of numbers it cannot vouch for.

struct Gauge: Equatable {
    /// nil = no reading (claudex printed —). That is not zero.
    var pct: Int?
    var at: String?
    static let none = Gauge(pct: nil, at: nil)
}

struct UsageRow: Equatable {
    var account: String
    var active: Bool
    var tier: String
    var session: Gauge
    var week: Gauge
    var updated: String
}

struct AccountRow: Equatable {
    var account: String
    var active: Bool
    var email: String
    var org: String
    var plan: String
    var saved: String
}

struct CurrentAccount: Equatable {
    var account: String
    var email: String
    var org: String
    var plan: String
}

struct PoolStatus: Equatable {
    var consuming: (on: Bool, detail: String)
    var sharing: (on: Bool, detail: String)

    static func == (a: PoolStatus, b: PoolStatus) -> Bool {
        a.consuming == b.consuming && a.sharing == b.sharing
    }
}

struct DoctorCheck: Equatable {
    var ok: Bool
    var label: String
    var detail: String
}

struct Doctor: Equatable {
    var checks: [DoctorCheck]
    var accounts: [DoctorCheck]
    var summary: String
}

struct PoolMember: Equatable {
    var name: String
    var plan: String
    /// ▶: claudex marks the member currently serving you.
    var marked: Bool
    var active: Bool
    var sharing: Bool
    var session: Gauge
    var week: Gauge
    /// Millions of tokens contributed (+) or borrowed (−).
    var netM: Double?
}

struct MemberFlow: Equatable {
    var label: String
    var `in`: String, out: String, cacheRead: String, cacheWrite: String, req: String
    var note: String
}

struct Driver: Equatable {
    var name: String
    var you: Bool
    var pct: Int
    var tokens: String
}

struct MemberWindow: Equatable {
    var label: String
    var pct: Int?
    var resets: String?
    var note: String?
    var drivers: [Driver]
}

struct MemberDetail: Equatable {
    var name: String
    var plan: String
    var marked: Bool
    var sharing: Bool
    var state: String
    var flows: [MemberFlow]
    var netM: Double?
    var netDir: String?
    var splitNote: String?
    var footnote: String?
    var windows: [MemberWindow]
}

struct AccessPerson: Equatable {
    var name: String
    var allowed: Bool
}

enum ClaudexParsers {
    private static let ansi = /\x1B\[[0-9;]*m/
    private static let cliError = /isn't a thing|does not exist|unrecognized arguments/
    private static let noData = "—"

    static func lines(_ text: String) -> [String] {
        text.replacing(ansi, with: "").components(separatedBy: "\n")
    }

    private static func num(_ s: Substring) -> Double? { Double(s.replacingOccurrences(of: "−", with: "-")) }

    // MARK: Tables

    /// "███░░░░░░░  30%  11:39pm" -> (30, "11:39pm"); "░░░░   —" -> no reading.
    static func gauge(_ cell: String) -> Gauge {
        let body = cell.filter { $0 != "█" && $0 != "░" }.trimmingCharacters(in: .whitespaces)
        if body.isEmpty || body.hasPrefix(noData) { return .none }
        guard let m = body.wholeMatch(of: /(\d+)\s*%\s*(.*)/) else { return .none }
        let at = m.2.trimmingCharacters(in: .whitespaces)
        return Gauge(pct: Int(m.1), at: at.isEmpty ? nil : at)
    }

    /// `usage` and `list` print the same box-drawing table.
    private static func boxTable(_ text: String) -> (headers: [String], rows: [[String]])? {
        var headers: [String]?
        var rows: [[String]] = []
        for line in lines(text) where line.contains("│") && line.firstMatch(of: /[┌┬┐├┼┤└┴┘]/) == nil {
            let cells = line.components(separatedBy: "│").dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
            if headers == nil { headers = cells } else { rows.append(Array(cells)) }
        }
        guard let headers, !rows.isEmpty else { return nil }
        return (headers, rows)
    }

    private static func cell(_ r: [String], _ i: Int) -> String { i < r.count ? r[i] : "" }

    static func usage(_ text: String) -> [UsageRow]? {
        guard text.firstMatch(of: cliError) == nil, let t = boxTable(text), t.headers.count > 3, t.headers[3] == "SESSION" else { return nil }
        return t.rows.map {
            UsageRow(account: cell($0, 1), active: cell($0, 0) == "●", tier: cell($0, 2),
                     session: gauge(cell($0, 3)), week: gauge(cell($0, 4)), updated: cell($0, 5))
        }
    }

    static func list(_ text: String) -> [AccountRow]? {
        guard text.firstMatch(of: cliError) == nil, let t = boxTable(text), t.headers.count > 2, t.headers[2] == "EMAIL" else { return nil }
        return t.rows.map {
            AccountRow(account: cell($0, 1), active: cell($0, 0) == "●", email: cell($0, 2), org: cell($0, 3), plan: cell($0, 4), saved: cell($0, 5))
        }
    }

    // MARK: current / pool status / doctor

    static func current(_ text: String) -> CurrentAccount? {
        guard text.firstMatch(of: cliError) == nil else { return nil }
        let ls = lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = ls.first, let m = first.wholeMatch(of: /[●○]\s+(.+)/) else { return nil }
        let parts = (ls.count > 2 ? ls[2] : "").components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        return CurrentAccount(account: String(m.1), email: ls.count > 1 ? ls[1] : "", org: parts.first ?? "", plan: parts.count > 1 ? parts[1] : "")
    }

    static func poolStatus(_ text: String) -> PoolStatus? {
        guard text.firstMatch(of: cliError) == nil else { return nil }
        var found: [String: (on: Bool, detail: String)] = [:]
        for line in lines(text) {
            if let m = line.wholeMatch(of: /\s*([●○])\s+(consuming|sharing)\s{2,}(.+?)\s*/) {
                found[String(m.2)] = (m.1 == "●", String(m.3))
            }
        }
        guard let c = found["consuming"], let s = found["sharing"] else { return nil }
        return PoolStatus(consuming: c, sharing: s)
    }

    static func doctor(_ text: String) -> Doctor? {
        guard text.firstMatch(of: cliError) == nil else { return nil }
        var checks: [DoctorCheck] = [], accounts: [DoctorCheck] = []
        var summary = ""
        var inAccounts = false
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "accounts:" { inAccounts = true; continue }
            if let s = line.wholeMatch(of: /●\s+(\d+\s+ok.*)/) { summary = String(s.1); continue }
            if let m = line.wholeMatch(of: /([✓✗])\s+(.+?)(?:\s{2,}(.+))?/) {
                let check = DoctorCheck(ok: m.1 == "✓", label: m.2.trimmingCharacters(in: .whitespaces),
                                        detail: (m.3.map(String.init) ?? "").trimmingCharacters(in: .whitespaces))
                if inAccounts { accounts.append(check) } else { checks.append(check) }
            }
        }
        return checks.isEmpty ? nil : Doctor(checks: checks, accounts: accounts, summary: summary)
    }

    // MARK: pool members

    static func poolMembers(_ text: String) -> [PoolMember]? {
        guard text.firstMatch(of: cliError) == nil else { return nil }
        var members: [PoolMember] = []
        for line in lines(text) {
            if let m = line.wholeMatch(of: /\s*(▶)?\s*([●○])\s+(\S+)\s+·\s+(.+?)\s+·\s+[●○]\s*(on|off)\s*/) {
                members.append(PoolMember(name: String(m.3), plan: String(m.4), marked: m.1 != nil, active: m.2 == "●",
                                          sharing: m.5 == "on", session: .none, week: .none, netM: nil))
                continue
            }
            guard !members.isEmpty, let g = line.wholeMatch(of: /\s+(session|week)\s+(.+)/) else { continue }
            var rest = String(g.2)
            if let net = rest.firstMatch(of: /\s+net\s+([+−\-]?[\d.]+)M\s*$/) {
                members[members.count - 1].netM = num(net.1)
                rest = String(rest[..<net.range.lowerBound])
            }
            if g.1 == "session" { members[members.count - 1].session = gauge(rest) } else { members[members.count - 1].week = gauge(rest) }
        }
        return members.isEmpty ? nil : members
    }

    // MARK: pool member (details)

    static func memberDetail(_ text: String) -> MemberDetail? {
        guard text.firstMatch(of: cliError) == nil else { return nil }
        let all = lines(text)
        guard let head = all.lazy.compactMap({ $0.wholeMatch(of: /\s*╭─\s+(\S+)\s+·\s+(.+?)\s*─+╮\s*/) }).first else { return nil }
        var d = MemberDetail(name: String(head.1), plan: head.2.trimmingCharacters(in: .whitespaces), marked: false, sharing: false, state: "",
                             flows: [], netM: nil, netDir: nil, splitNote: nil, footnote: nil, windows: [])
        var win: Int?
        for raw in all where raw.contains("│") {
            let line = raw.replacing(/^\s*│/, with: "").replacing(/│\s*$/, with: "")
            if let st = line.wholeMatch(of: /\s*(▶|[●○])\s+([●○])\s*(on|off)\s+(\S+)\s*/) {
                d.marked = st.1 == "▶"; d.sharing = st.3 == "on"; d.state = String(st.4)
            } else if let f = line.wholeMatch(of: /\s*(own|borrowed|shared)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*(.*?)\s*/) {
                d.flows.append(MemberFlow(label: String(f.1), in: String(f.2), out: String(f.3), cacheRead: String(f.4),
                                          cacheWrite: String(f.5), req: String(f.6), note: String(f.7)))
            } else if let n = line.wholeMatch(of: /\s*net give\/take\s+([+−\-]?[\d.]+)M\s+[↑↓]\s*(giver|taker)\s*/) {
                d.netM = num(n.1); d.netDir = String(n.2)
            } else if let sp = line.wholeMatch(of: /\s*USAGE SPLIT\s*(?:·\s*(.+?))?\s*/) {
                d.splitNote = sp.1.map(String.init)
            } else if let w = line.wholeMatch(of: /\s*(.+?)\s+(\d+|—)%\s+used\s*(?:·\s*resets\s+(.+?))?\s*/) {
                d.windows.append(MemberWindow(label: String(w.1), pct: Int(w.2), resets: w.3.map(String.init), note: nil, drivers: []))
                win = d.windows.count - 1
            } else if let dr = line.wholeMatch(of: /\s+(.+?)\s*(\(you\))?\s+[█░]+\s+(\d+)%\s+(\S+)\s*/), let i = win {
                d.windows[i].drivers.append(Driver(name: String(dr.1), you: dr.2 != nil, pct: Int(dr.3) ?? 0, tokens: String(dr.4)))
            } else if line.firstMatch(of: /^ {4,}\S/) != nil {
                if let i = win, d.windows[i].note == nil { d.windows[i].note = line.trimmingCharacters(in: .whitespaces) }
            } else if line.firstMatch(of: /^ {2,3}\S/) != nil {
                d.footnote = line.trimmingCharacters(in: .whitespaces)
            }
        }
        return d.flows.contains { $0.label == "own" } ? d : nil
    }

    // MARK: access

    /// `access`: who may borrow your account. A recognised-but-empty box is [] (an ordinary state), not nil.
    static func access(_ text: String) -> [AccessPerson]? {
        guard text.firstMatch(of: cliError) == nil else { return nil }
        let ls = lines(text)
        guard ls.contains(where: { $0.contains("Access to your account") }) else { return nil }
        return ls.filter { $0.contains("│") }.compactMap { raw in
            let line = raw.replacing(/^\s*│/, with: "").replacing(/│\s*$/, with: "")
            return line.wholeMatch(of: /\s*[●○]\s+(\S+)\s+(allowed|blocked)\s*/).map { AccessPerson(name: String($0.1), allowed: $0.2 == "allowed") }
        }
    }
}

// MARK: - Sorting (port of claudex-dash public/sort.js)

enum ClaudexSort: String, CaseIterable, Identifiable {
    case standard, nameAsc, nameDesc, weekAsc, weekDesc, sessionAsc, sessionDesc, resetAsc, weekReset
    var id: String { rawValue }

    /// Same labels and order as the designs' sort menu; `SampleData.sortOptions` mirrors them.
    var label: String {
        switch self {
        case .standard: "Default order"
        case .nameAsc: "Name A→Z"
        case .nameDesc: "Name Z→A"
        case .weekAsc: "Least used (week)"
        case .weekDesc: "Most used (week)"
        case .sessionAsc: "Least used (session)"
        case .sessionDesc: "Most used (session)"
        case .resetAsc: "Expiring soon"
        case .weekReset: "Least used + expiring soon"
        }
    }

    struct Key {
        var name: String
        var session: Int?
        var week: Int?
        var reset: Date?
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// A gauge's `at` string ("Aug 20 1:09am", or a bare "11:39pm") -> a date. nil when there is nothing to read.
    static func resetAt(_ at: String?, now: Date = Date()) -> Date? {
        guard let at, let m = at.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(?:([A-Za-z]{3})\s+(\d{1,2})\s+)?(\d{1,2}):(\d{2})\s*(am|pm)/.ignoresCase()),
              let hour = Int(m.3), let minute = Int(m.4) else { return nil }
        let h = hour % 12 + (m.5.lowercased() == "pm" ? 12 : 0)
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = h; c.minute = minute
        guard let mon = m.1, let day = m.2 else { return cal.date(from: c) }
        guard let month = months.firstIndex(of: mon.lowercased()) else { return nil }
        c.month = month + 1; c.day = Int(day)
        guard let t = cal.date(from: c) else { return nil }
        // No year in the input: a December reset read in January would otherwise land 11 months in the past.
        if now.timeIntervalSince(t) > 183 * 24 * 3600, let next = cal.date(byAdding: .year, value: 1, to: t) { return next }
        return t
    }

    /// Never mutates; unknown readings sink to the end in both directions.
    func apply<T>(_ rows: [T], key: (T) -> Key) -> [T] {
        let indexed = rows.enumerated().map { (i: $0.offset, row: $0.element, key: key($0.element)) }
        func by<V: Comparable>(_ v: @escaping (Key) -> V?, _ dir: Int) -> (Int, Int) -> Bool {
            { a, b in
                let x = v(indexed[a].key), y = v(indexed[b].key)
                if x == nil || y == nil { return x == nil && y == nil ? a < b : y == nil }
                return x! == y! ? a < b : (dir > 0 ? x! < y! : x! > y!)
            }
        }
        let order: [Int]
        switch self {
        case .standard: order = Array(indexed.indices)
        case .nameAsc: order = indexed.indices.sorted { let c = indexed[$0].key.name.localizedStandardCompare(indexed[$1].key.name); return c == .orderedSame ? $0 < $1 : c == .orderedAscending }
        case .nameDesc: order = indexed.indices.sorted { let c = indexed[$0].key.name.localizedStandardCompare(indexed[$1].key.name); return c == .orderedSame ? $0 < $1 : c == .orderedDescending }
        case .weekAsc: order = indexed.indices.sorted(by: by({ $0.week }, 1))
        case .weekDesc: order = indexed.indices.sorted(by: by({ $0.week }, -1))
        case .sessionAsc: order = indexed.indices.sorted(by: by({ $0.session }, 1))
        case .sessionDesc: order = indexed.indices.sorted(by: by({ $0.session }, -1))
        case .resetAsc: order = indexed.indices.sorted(by: by({ $0.reset }, 1))
        case .weekReset:
            // Two axes with no common unit, blended by rank (equal weight): ponytail: scale one rank to weight it.
            func ranks(_ cmp: (Int, Int) -> Bool) -> [Int: Int] {
                Dictionary(uniqueKeysWithValues: indexed.indices.sorted(by: cmp).enumerated().map { ($0.element, $0.offset) })
            }
            let used = ranks(by({ $0.week }, 1)), soon = ranks(by({ $0.reset }, 1))
            order = indexed.indices.sorted { a, b in
                let x = used[a]! + soon[a]!, y = used[b]! + soon[b]!
                return x == y ? a < b : x < y
            }
        }
        return order.map { indexed[$0].row }
    }
}
