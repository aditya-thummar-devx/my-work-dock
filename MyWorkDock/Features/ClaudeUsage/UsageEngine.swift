import Foundation

/// Reads Claude Code's transcripts and keeps the `UsageLedger`: finds the files that changed since the last look, reads only their new
/// bytes (several at once), folds the calls in and saves. The first look reads everything (a heavy month is a few GB: under three
/// seconds on an M-series Mac); later ones read what was appended and take tens of milliseconds.
actor UsageEngine {
    /// `~/.claude/projects`
    static var defaultRoot: URL { URL(fileURLWithPath: NSHomeDirectory() + "/.claude/projects") }
    static var defaultStateURL: URL { JSONFile.url("claude-usage.json") }

    let root: URL
    private let stateURL: URL?
    private var ledger = UsageLedger()
    private var loaded = false
    private var busy = false
    /// `lastScan` as last written: a refresh that finds nothing new leaves the file alone, until it is a day behind.
    private var savedLastScan: Double?
    /// Why the last save failed; nil when it worked or nothing was saved.
    private(set) var saveError: String?

    /// `stateURL == nil` keeps everything in memory (tests). Nothing is read until the first `refresh`.
    init(root: URL = UsageEngine.defaultRoot, stateURL: URL? = UsageEngine.defaultStateURL) {
        self.root = root
        self.stateURL = stateURL
    }

    /// The saved totals, read on first use (here, off the caller's thread: the init runs on it).
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let stateURL, FileManager.default.fileExists(atPath: stateURL.path) else { return }
        if let saved = JSONFile.load(UsageLedger.self, from: stateURL) {
            ledger = saved
            savedLastScan = saved.lastScan
            return
        }
        // Unreadable, whether damaged or written by a newer version. What it held cannot be recomputed once Claude Code has deleted
        // the transcripts, so it is put aside instead of being overwritten by a fresh start.
        let aside = stateURL.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: stateURL, to: aside)
    }

    func snapshot(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> UsageSnapshot {
        load()
        var s = ledger.snapshot(now: now, calendar: calendar)
        s.noData = ledger.days.isEmpty && ledger.files.isEmpty
        return s
    }

    /// One look at the transcripts. A second call while one runs returns what is known so far.
    func refresh(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async -> UsageSnapshot {
        guard !busy else { return snapshot(now: now, calendar: calendar) }
        busy = true
        defer { busy = false }
        load()

        let listing = Self.transcripts(under: root)
        let jobs: [TranscriptScanner.Job] = listing.files.compactMap { f in
            let known = ledger.files[f.path]
            if let known, known.size == f.size, known.mtime == f.mtime { return nil }
            return TranscriptScanner.Job(path: f.path, offset: known?.offset ?? 0, head: known?.head ?? "", headLength: known?.headLength ?? 0)
        }
        let mtimes = Dictionary(listing.files.map { ($0.path, $0.mtime) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for out in await Self.scan(jobs).sorted(by: { $0.path < $1.path }) where !out.failed {
            ledger.add(out.calls, now: now, calendar: calendar)
            ledger.files[out.path] = FileMark(offset: out.consumed, size: out.size, mtime: mtimes[out.path] ?? 0, head: out.head, headLength: out.headLength)
            changed = true
        }
        // Only a listing that reached every file says which transcripts are gone, or that the folder has been seen. A folder that is missing
        // or cannot be read (an unmounted volume) says nothing: forgetting every read position then would read every file again.
        if listing.complete {
            if ledger.noteScan(now: now) { changed = true }
            // A deleted transcript leaves its counted calls in the totals; only its read position goes.
            let gone = ledger.files.keys.filter { mtimes[$0] == nil }
            for path in gone { ledger.files[path] = nil }
            if !gone.isEmpty { changed = true }
        }
        if ledger.prune(now: now) { changed = true }

        if changed || (ledger.lastScan ?? 0) - (savedLastScan ?? 0) > 86_400 {
            saveError = JSONFile.save(ledger, to: stateURL)
            savedLastScan = ledger.lastScan
        }
        return snapshot(now: now, calendar: calendar)
    }

    // MARK: Files

    struct Found { var path: String; var size: Int; var mtime: Double }

    /// Every `.jsonl` under `root`: the sessions and, below them, their subagents. `complete` is false when the folder is missing or cannot
    /// be read, or an entry in it could not be examined: such a listing must not be taken to mean that the files missing from it are gone.
    static func transcripts(under root: URL) -> (files: [Found], complete: Bool) {
        let base = root.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else { return ([], false) }
        final class Flag { var complete = true }
        let flag = Flag()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
                                                        errorHandler: { _, _ in flag.complete = false; return true }) else { return ([], false) }
        var found: [Found] = []
        for case let url as URL in walk where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { flag.complete = false; continue }
            guard v.isRegularFile == true else { continue }
            found.append(Found(path: url.path, size: v.fileSize ?? 0, mtime: v.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        return (found, flag.complete)
    }

    /// Scans `jobs` a few at a time, off the low-priority pool, so a first read of gigabytes does not take every core.
    private static func scan(_ jobs: [TranscriptScanner.Job]) async -> [TranscriptScanner.Output] {
        let width = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount / 2))
        var outputs: [TranscriptScanner.Output] = []
        var next = 0
        await withTaskGroup(of: TranscriptScanner.Output.self) { group in
            while next < jobs.count, next < width {
                let job = jobs[next]
                next += 1
                group.addTask(priority: .utility) { TranscriptScanner.scan(job) }
            }
            while let done = await group.next() {
                outputs.append(done)
                if next < jobs.count {
                    let job = jobs[next]
                    next += 1
                    group.addTask(priority: .utility) { TranscriptScanner.scan(job) }
                }
            }
        }
        return outputs
    }
}
