import Foundation

/// A Claude Code session read from its transcript (`~/.claude/projects/<encoded-cwd>/<id>.jsonl`).
struct Transcript: Identifiable, Equatable, Sendable {
    var id: String
    var cwd: String?
    var project: String
    var branch: String?
    var title: String
    var lastActivity: Date
    var model: String?
    var contextTokens: Int?
    var contextWindow: Int

    var contextPercent: Int? { contextTokens.map { min(100, Int((Double($0) / Double(contextWindow) * 100).rounded())) } }
}

/// Index of recent transcripts. Files are re-read only when their (mtime, size) changes, so a rescan
/// is cheap. Not thread-safe: use from one task at a time.
final class TranscriptIndex: @unchecked Sendable {
    static let maxAge: TimeInterval = 30 * 86_400
    static let maxSessions = 200
    private static let titleChars = 80

    let root: URL
    private var cache: [URL: (key: String, session: Transcript?)] = [:]
    /// Files actually parsed (tests, diagnostics).
    private(set) var parses = 0

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    func scan(now: Date = Date()) -> [Transcript] {
        let fm = FileManager.default
        var seen: Set<URL> = []
        var out: [Transcript] = []
        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let files = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                guard let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = v.contentModificationDate, now.timeIntervalSince(mtime) <= Self.maxAge else { continue }
                seen.insert(f)
                let key = "\(mtime.timeIntervalSince1970)-\(v.fileSize ?? 0)"
                if let c = cache[f], c.key == key {
                    if let s = c.session { out.append(s) }
                    continue
                }
                parses += 1
                let s = Self.parse(f)
                cache[f] = (key, s)
                if let s { out.append(s) }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        return Array(out.sorted { ($0.lastActivity, $1.id) > ($1.lastActivity, $0.id) }.prefix(Self.maxSessions))
    }

    /// Title of one session for the live Agents list. Uses any cached parse (titles rarely change,
    /// transcripts grow constantly); reads the file once if it was never seen.
    func title(for id: String) -> String? {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        let name = "\(id).jsonl"
        if let hit = cache.first(where: { $0.key.lastPathComponent == name }) { return hit.value.session?.title }
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        guard let f = projects.map({ $0.appendingPathComponent(name) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        parses += 1
        let s = Self.parse(f)
        cache[f] = ("", s) // empty key: the next full scan refreshes it
        return s?.title
    }

    private static func truncate(_ s: String) -> String {
        let s = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return s.count <= titleChars ? s : String(s.prefix(titleChars)) + "…"
    }

    /// The user's typed prompt, skipping meta records, tool results and command wrappers.
    private static func promptText(_ r: [String: Any]) -> String? {
        if r["isMeta"] as? Bool == true { return nil }
        let content = (r["message"] as? [String: Any])?["content"]
        let text: String?
        if let s = content as? String { text = s }
        else if let items = content as? [[String: Any]] { text = items.first { $0["type"] as? String == "text" }?["text"] as? String }
        else { text = nil }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.hasPrefix("<") else { return nil }
        return truncate(t)
    }

    /// Parses one transcript; unreadable lines are skipped, a file with no records gives nil.
    static func parse(_ url: URL) -> Transcript? {
        guard let data = try? Data(contentsOf: url),
              let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        var cwd: String?, branch: String?, model: String?, custom: String?, ai: String?, first: String?, tokens: Int?
        var large = false, seen = false
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let r = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            seen = true
            func s(_ k: String) -> String? { (r[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            if let c = s("cwd") { cwd = c }
            if let b = s("gitBranch") { branch = b }
            switch r["type"] as? String {
            case "custom-title": custom = s("customTitle") ?? custom
            case "ai-title": ai = s("aiTitle") ?? ai
            case "user" where first == nil: first = promptText(r)
            case "assistant" where r["isSidechain"] as? Bool != true:
                let msg = r["message"] as? [String: Any]
                if let u = msg?["usage"] as? [String: Any] {
                    func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
                    tokens = n("input_tokens") + n("cache_read_input_tokens") + n("cache_creation_input_tokens")
                }
                if let m = msg?["model"] as? String { model = m }
                if s("requestedModel")?.contains("[1m]") == true { large = true }
            default: break
            }
        }
        guard seen else { return nil }
        if let tokens, tokens > 200_000 { large = true }
        return Transcript(id: url.deletingPathExtension().lastPathComponent, cwd: cwd, project: projectName(cwd), branch: branch,
                          title: (custom ?? ai).map(truncate) ?? first ?? "Untitled session",
                          lastActivity: mtime, model: model, contextTokens: tokens, contextWindow: large ? 1_000_000 : 200_000)
    }
}
