import Foundation

/// Finds the terminal an agent runs on and types prompts into Terminal.app / iTerm2 tabs.
enum TerminalLookup {
    /// Walks up from `pid` to the first ancestor with a terminal: Claude Code runs hooks through a
    /// shell that has none, the `claude` process above it does. `info(pid)` → (parent, tty).
    static func walk(_ pid: Int32, info: (Int32) -> (Int32, String?)?) -> String? { owner(pid, info: info)?.tty }

    /// Like `walk`, plus the process that owns the terminal: the `claude` process itself, which the Agents tab watches to drop
    /// sessions whose terminal was closed.
    static func owner(_ pid: Int32, info: (Int32) -> (Int32, String?)?) -> (pid: Int32, tty: String)? {
        var pid = pid
        for _ in 0..<8 {
            guard let (parent, tty) = info(pid) else { return nil }
            if let tty { return (pid, tty) }
            if parent <= 1 || parent == pid { return nil }
            pid = parent
        }
        return nil
    }

    /// One `ps` for the whole process table, then the walk is in memory.
    static func tty(_ pid: Int32) async -> (pid: Int32, tty: String)? {
        let r = await ProcessRunner.run("/bin/ps", ["-A", "-o", "pid=,ppid=,tty="], timeout: 5)
        guard r.ok else { return nil }
        let table = parsePS(r.out)
        return owner(pid) { table[$0] }
    }

    /// The process still exists (signal 0 only checks; EPERM means it exists but belongs to someone else).
    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    /// `ps -A -o pid=,ppid=,tty=` → pid → (parent, tty or nil for "??").
    static func parsePS(_ out: String) -> [Int32: (Int32, String?)] {
        var table: [Int32: (Int32, String?)] = [:]
        for line in out.split(whereSeparator: \.isNewline) {
            let f = line.split(whereSeparator: \.isWhitespace)
            guard f.count >= 3, let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            table[pid] = (ppid, f[2].hasPrefix("?") ? nil : String(f[2]))
        }
        return table
    }

    /// AppleScript string body: no control characters (a newline would submit early), escaped.
    static func appleScriptText(_ s: String) -> String {
        let flat = String(s.unicodeScalars.compactMap { c -> Character? in
            if c == "\n" || c == "\r" || c == "\t" { return " " }
            if CharacterSet.controlCharacters.contains(c) { return nil }
            return Character(c)
        })
        return flat.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Scripts that type `text` + Return into the Terminal / iTerm2 tab on `tty`. Guarded by
    /// `is running` so an app that isn't open is never launched; each prints "ok" on success.
    static func typingScripts(tty: String, text: String, iterm: Bool) -> [String] {
        let name = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber }) else { return [] }
        let dev = "/dev/\(name)", t = appleScriptText(text)
        var scripts = ["""
        if application "Terminal" is running then
        tell application "Terminal"
        repeat with w in windows
        repeat with tb in tabs of w
        if tty of tb is "\(dev)" then
        do script "\(t)" in tb
        return "ok"
        end if
        end repeat
        end repeat
        end tell
        end if
        return "missing"
        """]
        if iterm {
            scripts.append("""
            if application "iTerm2" is running then
            tell application "iTerm2"
            repeat with w in windows
            repeat with tb in tabs of w
            repeat with s in sessions of tb
            if tty of s is "\(dev)" then
            tell s to write text "\(t)"
            return "ok"
            end if
            end repeat
            end repeat
            end repeat
            end tell
            end if
            return "missing"
            """)
        }
        return scripts
    }

    /// Types into the agent's tab. False when no supported terminal owns `tty`.
    static func type(tty: String, text: String) async throws -> Bool {
        let iterm = FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
        for script in typingScripts(tty: tty, text: text, iterm: iterm) {
            let r = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 10)
            if r.ok && r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" { return true }
            if r.err.contains("-1743") {
                throw AgentError("Allow MyWorkDock to control Terminal in System Settings › Privacy & Security › Automation.")
            }
        }
        return false
    }
}

