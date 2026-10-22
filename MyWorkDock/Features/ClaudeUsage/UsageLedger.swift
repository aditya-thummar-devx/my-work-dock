import Foundation

/// Where the last scan of one transcript stopped, and what the file looked like then.
struct FileMark: Codable, Equatable, Sendable {
    var offset: Int
    var size: Int
    var mtime: Double
    /// Fingerprint of the first `headLength` bytes: a transcript only grows at its end, so a changed start means a different file.
    var head = ""
    var headLength = 0
}

/// A call from the last six hours, kept whole: the rolling five-hour figure needs timestamps, and a later chunk of the same
/// message can still raise its tokens.
struct RecentCall: Codable, Equatable, Sendable {
    var key: CallKey
    var t: Double
    var model: String
    var tokens: TokenCounts
}

/// Day label of a timestamp in a calendar ("2026-10-21"); remembers the last day it computed, since calls arrive in runs.
struct DayKeyer {
    let calendar: Calendar
    private var start = 0.0
    private var end = 0.0
    private var cached = ""

    init(calendar: Calendar) { self.calendar = calendar }

    mutating func key(_ t: Double) -> String {
        if t >= start, t < end { return cached }
        let date = Date(timeIntervalSince1970: t)
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        cached = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let dayStart = calendar.startOfDay(for: date)
        start = dayStart.timeIntervalSince1970
        end = (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)).timeIntervalSince1970
        return cached
    }
}

/// Everything remembered between launches, in Application Support. Totals are only ever added to, never recomputed from
/// transcripts: Claude Code deletes a transcript 30 days after its last write, and what was counted before stays counted.
struct UsageLedger: Codable, Equatable, Sendable {
    /// How long a call stays in `recent`.
    static let recentWindow: TimeInterval = 6 * 3600
    /// The rolling window of the first card.
    static let fiveHours: TimeInterval = 5 * 3600
    /// Ids older than this are forgotten. A call that old that is counted again lands on a day nobody looks at (the tab shows this and last month).
    static let seenDays = 120
    /// Claude Code deletes a transcript this long after its last write (its default `cleanupPeriodDays`).
    static let transcriptLife: TimeInterval = 30 * 86400

    /// When the transcript folder was last read in full.
    var lastScan: Double?
    /// The oldest moment from which every call is known to be counted. The first look can see everything made in the last 30 days, since a
    /// transcript outlives each call in it by at least that long. A look more than 30 days after the one before may have missed what was made
    /// and deleted in between, so from there coverage starts again.
    var coveredFrom: Double?
    var files: [String: FileMark] = [:]
    /// "2026-10-21" -> model -> tokens: the archive behind Today, This month and Last month.
    var days: [String: [String: TokenCounts]] = [:]
    private(set) var recent: [RecentCall] = []
    /// Every call already counted -> its UTC day number. Makes a rescan, or a resumed session's copy of old lines, add nothing.
    private(set) var seen: [CallKey: Int32] = [:]
    private var recentIndex: [CallKey: Int] = [:]

    init() {}

    // MARK: Adding

    /// Counts each call once. A call already in `recent` can still grow (a later chunk of the same message); older ones are final.
    /// Returns whether anything changed.
    @discardableResult
    mutating func add(_ calls: [ParsedCall], now: Date, calendar: Calendar) -> Bool {
        var keyer = DayKeyer(calendar: calendar)
        let horizon = now.timeIntervalSince1970 - Self.recentWindow
        var changed = false
        for c in calls.sorted(by: { $0.t < $1.t }) {
            if let i = recentIndex[c.key] {
                let grown = recent[i].tokens.raised(to: c.tokens)
                if grown != recent[i].tokens {
                    addToDay(keyer.key(recent[i].t), recent[i].model, grown - recent[i].tokens)
                    recent[i].tokens = grown
                    changed = true
                }
                continue
            }
            if seen[c.key] != nil { continue }
            seen[c.key] = Int32(c.t / 86400)
            addToDay(keyer.key(c.t), c.model, c.tokens)
            if c.t >= horizon {
                recentIndex[c.key] = recent.count
                recent.append(RecentCall(key: c.key, t: c.t, model: c.model, tokens: c.tokens))
            }
            changed = true
        }
        return changed
    }

    private mutating func addToDay(_ day: String, _ model: String, _ tokens: TokenCounts) {
        days[day, default: [:]][model, default: TokenCounts()] += tokens
    }

    /// Drops what has aged out. Returns whether anything was dropped.
    @discardableResult
    mutating func prune(now: Date) -> Bool {
        var changed = false
        let horizon = now.timeIntervalSince1970 - Self.recentWindow
        if recent.contains(where: { $0.t < horizon }) {
            recent.removeAll { $0.t < horizon }
            rebuildIndex()
            changed = true
        }
        let cutoff = Int32(now.timeIntervalSince1970 / 86400) - Int32(Self.seenDays)
        if seen.contains(where: { $0.value < cutoff }) {
            seen = seen.filter { $0.value >= cutoff }
            changed = true
        }
        return changed
    }

    private mutating func rebuildIndex() {
        recentIndex = [:]
        for (i, c) in recent.enumerated() { recentIndex[c.key] = i }
    }

    /// A look at the whole transcript folder at `now` has finished. Returns whether the coverage changed.
    @discardableResult
    mutating func noteScan(now: Date) -> Bool {
        let t = now.timeIntervalSince1970
        let horizon = t - Self.transcriptLife
        let before = coveredFrom
        if let last = lastScan, let covered = coveredFrom {
            coveredFrom = last >= horizon ? covered : horizon
            lastScan = max(last, t)
        } else {
            coveredFrom = horizon
            lastScan = t
        }
        return coveredFrom != before
    }

    // MARK: Reading

    func snapshot(now: Date, calendar: Calendar) -> UsageSnapshot {
        var keyer = DayKeyer(calendar: calendar)
        let t = now.timeIntervalSince1970
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let lastStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart

        var five = UsageFigures()
        var since: Double?
        for c in recent where c.t >= t - Self.fiveHours {
            five.add(c.tokens, model: c.model)
            since = min(since ?? c.t, c.t)
        }
        let today = keyer.key(t)
        let monthPrefix = Self.prefix(of: monthStart, calendar)
        let lastPrefix = Self.prefix(of: lastStart, calendar)
        return UsageSnapshot(fiveHours: five,
                             windowSince: since.map { Date(timeIntervalSince1970: $0) },
                             today: figures { $0 == today },
                             month: figures { $0.hasPrefix(monthPrefix) },
                             lastMonth: figures { $0.hasPrefix(lastPrefix) },
                             monthStart: monthStart,
                             lastMonthStart: lastStart,
                             monthPartialFrom: completeFrom(monthStart: monthStart, calendar: calendar),
                             lastMonthPartialFrom: completeFrom(monthStart: lastStart, calendar: calendar),
                             updatedAt: now)
    }

    private func figures(where include: (String) -> Bool) -> UsageFigures {
        var f = UsageFigures()
        for (day, models) in days where include(day) {
            for (model, tokens) in models { f.add(tokens, model: model) }
        }
        return f
    }

    /// The first day from which the month that starts at `monthStart` is complete; nil when it is complete from its first day, or when
    /// nothing has been scanned yet. A month that ended before `coveredFrom` has no such day: the result is on or after its end.
    func completeFrom(monthStart: Date, calendar: Calendar) -> Date? {
        guard let coveredFrom else { return nil }
        let covered = Date(timeIntervalSince1970: coveredFrom)
        guard monthStart < covered else { return nil }
        let day = calendar.startOfDay(for: covered)
        // The day coverage starts in is only covered from that moment on, so the first whole day is the next one.
        return day == covered ? day : calendar.date(byAdding: .day, value: 1, to: day)
    }

    private static func prefix(of date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    // MARK: Saving

    private enum CodingKeys: String, CodingKey { case lastScan, coveredFrom, files, days, recent, seen }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastScan = try c.decodeIfPresent(Double.self, forKey: .lastScan)
        coveredFrom = try c.decodeIfPresent(Double.self, forKey: .coveredFrom)
        files = try c.decodeIfPresent([String: FileMark].self, forKey: .files) ?? [:]
        days = try c.decodeIfPresent([String: [String: TokenCounts]].self, forKey: .days) ?? [:]
        // One entry per call: a damaged file that lists a call twice keeps the larger counts.
        var position: [CallKey: Int] = [:]
        for call in try c.decodeIfPresent([RecentCall].self, forKey: .recent) ?? [] {
            if let i = position[call.key] {
                recent[i].tokens = recent[i].tokens.raised(to: call.tokens)
            } else {
                position[call.key] = recent.count
                recent.append(call)
            }
        }
        // Ids are saved packed, 8 bytes each, grouped by day: a month of calls stays under half a megabyte.
        for (day, blob) in try c.decodeIfPresent([String: Data].self, forKey: .seen) ?? [:] {
            guard let n = Int32(day) else { continue }
            blob.withUnsafeBytes { raw in
                for offset in stride(from: 0, to: raw.count - 7, by: 8) {
                    seen[CallKey(raw: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))] = n
                }
            }
        }
        rebuildIndex()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(lastScan, forKey: .lastScan)
        try c.encodeIfPresent(coveredFrom, forKey: .coveredFrom)
        try c.encode(files, forKey: .files)
        try c.encode(days, forKey: .days)
        try c.encode(recent, forKey: .recent)
        var byDay: [Int32: [UInt64]] = [:]
        for (key, n) in seen { byDay[n, default: []].append(key.raw) }
        var packed: [String: Data] = [:]
        for (n, ids) in byDay { packed[String(n)] = ids.withUnsafeBytes { Data($0) } }
        try c.encode(packed, forKey: .seen)
    }
}
