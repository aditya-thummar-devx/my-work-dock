import Foundation

/// Installs MyWorkDock's hooks into `~/.claude/settings.json`. Always backs the file up first, keeps
/// the user's own hooks, and refuses to touch a file that isn't a JSON object.
struct ClaudeHookInstaller {
    /// Every command we install contains this; uninstall removes exactly those entries.
    static let marker = "mwd-hook"

    var configURL: URL
    /// The hook shipped inside the app bundle.
    var bundledHook: URL
    /// Stable copy the installed commands point at, so moving or updating the app never breaks Claude.
    var binDir: URL
    var backupDir: URL
    var approvalTimeout = 600

    enum Wait { case no, approval, question, wake }

    /// (hook event, matcher, `--event` passed to mwd-hook, how it waits)
    static let events: [(String, String?, String, Wait)] = [
        ("SessionStart", nil, "SessionStart", .no),
        ("SessionStart", nil, "Wake", .wake),
        ("SessionEnd", nil, "SessionEnd", .no),
        ("UserPromptSubmit", nil, "UserPromptSubmit", .no),
        ("PostToolUse", "*", "PostToolUse", .no),
        ("Notification", nil, "Notification", .no),
        ("Stop", nil, "Stop", .no),
        ("Stop", nil, "Wake", .wake),
        ("PreToolUse", "AskUserQuestion", "PreToolUse", .question),
        ("PermissionRequest", "*", "PermissionRequest", .approval),
    ]

    struct Status: Equatable {
        var installed: Bool
        /// Our entries exist but are outdated or point at a missing binary: install again to repair.
        var stale: Bool
        var error: String?
    }

    enum InstallError: LocalizedError {
        case malformed(String)
        var errorDescription: String? {
            if case .malformed(let s) = self { return "Claude's settings file isn't valid JSON (\(s)). Fix it, then try again." }
            return nil
        }
    }

    static func live() -> ClaudeHookInstaller {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyWorkDock")
        return ClaudeHookInstaller(
            configURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json"),
            bundledHook: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mwd-hook"),
            binDir: support.appendingPathComponent("bin"),
            backupDir: support.appendingPathComponent("backups"))
    }

    var deployedHook: URL { binDir.appendingPathComponent("mwd-hook") }

    /// (hook event, matcher, command, timeout seconds, background rewake)
    func expected() -> [(String, String?, String, Int, Bool)] {
        Self.events.map { event, matcher, arg, wait in
            let bin = "\"\(deployedHook.path)\" --agent claude --event \(arg)"
            switch wait {
            case .no: return (event, matcher, bin, 5, false)
            case .approval: return (event, matcher, "\(bin) --wait --timeout-secs \(approvalTimeout)", approvalTimeout + 10, false)
            case .question: return (event, matcher, "\(bin) --wait --timeout-secs 60", 70, false)
            case .wake: return (event, matcher, "\(bin) --wait --timeout-secs 86400", 86410, true)
            }
        }
    }

    func readConfig() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL) else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw InstallError.malformed(configURL.path)
        }
        return dict
    }

    func status() -> Status {
        do {
            let cfg = try readConfig()
            let text = String(decoding: (try? JSONSerialization.data(withJSONObject: cfg)) ?? Data(), as: UTF8.self)
            let installed = text.contains(Self.marker)
            let outdated = expected().contains { !commands(in: cfg).contains($0.2) }
            let missing = !FileManager.default.isExecutableFile(atPath: deployedHook.path)
            return Status(installed: installed, stale: installed && (outdated || missing), error: nil)
        } catch {
            return Status(installed: false, stale: false, error: error.localizedDescription)
        }
    }

    private func commands(in cfg: [String: Any]) -> Set<String> {
        var out: Set<String> = []
        for case let groups as [[String: Any]] in (cfg["hooks"] as? [String: Any] ?? [:]).values {
            for g in groups { for h in g["hooks"] as? [[String: Any]] ?? [] { if let c = h["command"] as? String { out.insert(c) } } }
        }
        return out
    }

    /// Removes every hook entry we own, dropping groups/events/the key only if we emptied them.
    static func stripOurs(_ cfg: inout [String: Any]) {
        guard var hooks = cfg["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            var changed = false
            for i in groups.indices {
                guard let hs = groups[i]["hooks"] as? [[String: Any]] else { continue }
                let kept = hs.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
                if kept.count != hs.count { groups[i]["hooks"] = kept; changed = true }
            }
            guard changed else { continue }
            groups.removeAll { ($0["hooks"] as? [Any])?.isEmpty ?? false }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        cfg["hooks"] = hooks.isEmpty ? nil : hooks
    }

    @discardableResult
    func install() throws -> URL? {
        var cfg = try readConfig()
        try deployHook()
        let backup = try self.backup()
        Self.stripOurs(&cfg)
        var hooks = cfg["hooks"] as? [String: Any] ?? [:]
        for (event, matcher, command, timeout, rewake) in expected() {
            var handler: [String: Any] = ["type": "command", "command": command, "timeout": timeout]
            if rewake { handler["asyncRewake"] = true }
            var group: [String: Any] = ["hooks": [handler]]
            if let matcher { group["matcher"] = matcher }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        cfg["hooks"] = hooks
        try write(cfg)
        return backup
    }

    func uninstall() throws {
        var cfg = try readConfig()
        try backup()
        Self.stripOurs(&cfg)
        try write(cfg)
    }

    /// Copies the bundled hook to its stable location (also on launch, so app updates refresh it).
    func deployHook() throws { try Self.deploy(bundledHook, to: deployedHook) }

    /// Atomically replaces `dest` with a copy of `src`; a process still running the old copy keeps it.
    static func deploy(_ src: URL, to dest: URL) throws {
        let dir = dest.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(dest.lastPathComponent + ".tmp")
        try? FileManager.default.removeItem(at: tmp)
        try FileManager.default.copyItem(at: src, to: tmp)
        _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
    }

    @discardableResult
    private func backup() throws -> URL? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        // Two writes inside the same millisecond (install then uninstall) must not collide.
        var dest = backupDir.appendingPathComponent("claude-settings-\(stamp).json")
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = backupDir.appendingPathComponent("claude-settings-\(stamp)-\(n).json")
            n += 1
        }
        try FileManager.default.copyItem(at: configURL, to: dest)
        return dest
    }

    private func write(_ cfg: [String: Any]) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: configURL, options: .atomic)
    }
}
