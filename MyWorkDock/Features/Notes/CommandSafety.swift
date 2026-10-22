import Foundation

/// Decides which saved commands get a Run button. A blocklist, so it has a ceiling: it cannot see through
/// `a=r; ${a}m -rf x`, a script file that holds the real command, or `python -c`. The confirm sheet, which shows the
/// whole command, is the second net. Copy still works on a blocked command.
enum CommandSafety {
    /// Why `command` must not be run from here; nil when it looks fine.
    static func blockedReason(_ command: String) -> String? {
        let whole = command.lowercased()
        for (pattern, reason) in wholeRules where whole.range(of: pattern, options: .regularExpression) != nil { return reason }
        // `$(…)`, backticks, groups and `&& || ; |` each start a new segment, so a command hidden inside one is still checked.
        let segments = command.components(separatedBy: CharacterSet(charactersIn: ";&|\n(){}`"))
        for segment in segments {
            if let reason = blockedWords(tokens(segment)) { return reason }
        }
        return nil
    }

    private static let wholeRules: [(pattern: String, reason: String)] = [
        (#"\|\s*(sudo\s+)?(env\s+)?(ba|z|da|k)?sh\b"#, "pipes into a shell"),
        (#":\s*\(\s*\)\s*\{"#, "looks like a fork bomb"),
        (#">\s*/dev/(r?disk|sd|nvme)"#, "writes straight to a disk"),
        (#"base64\s+(-d|--decode)[^|]*\|"#, "runs decoded text"),
        (#"\b(drop\s+(table|database|schema)|truncate\s+table)\b"#, "drops database data"),
    ]

    /// Commands that run what follows them: the rest is checked from every word on.
    private static let wrappers: Set<String> = [
        "xargs", "find", "timeout", "watch", "nice", "nohup", "time", "env", "command", "exec", "builtin", "setsid", "caffeinate", "stdbuf",
    ]
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish"]

    private static func tokens(_ segment: String) -> [String] {
        segment.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\\")) }.filter { !$0.isEmpty }
    }

    private static func blockedWords(_ words: [String]) -> String? {
        // Skip `VAR=value` prefixes.
        var words = Array(words.drop { $0.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil })
        guard let first = words.first else { return nil }
        let name = (first as NSString).lastPathComponent.lowercased()
        words.removeFirst()
        let args = words.map { $0.lowercased() }
        let flags = args.filter { $0.hasPrefix("-") && !$0.hasPrefix("--") }.map { $0.dropFirst() }

        switch name {
        case "sudo", "su", "doas": return "needs admin rights"
        case "rm":
            if flags.contains(where: { $0.contains("r") || $0.contains("f") }) || args.contains(where: { ["--recursive", "--force", "--no-preserve-root"].contains($0) }) {
                return "deletes files recursively or by force"
            }
            if args.contains(where: { $0 == "/" || $0 == "~" || $0.contains("*") }) { return "deletes many files" }
        case "dd", "fdisk", "diskutil", "shred", "truncate": return "can destroy data"
        case _ where name.hasPrefix("mkfs"): return "formats a disk"
        case "shutdown", "reboot", "halt", "poweroff": return "turns the Mac off"
        case "killall", "pkill": return "kills processes by name"
        case "kill":
            if flags.contains(where: { $0 == "9" || $0 == "kill" || $0 == "sigkill" }) { return "force-kills a process" }
        case "chmod", "chown", "chgrp":
            if flags.contains(where: { $0.contains("r") }) { return "changes permissions recursively" }
        case "launchctl": return "changes system services"
        case "eval": return "runs text as code"
        case "defaults":
            if args.contains("delete") { return "deletes app settings" }
        case "git": return blockedGit(args, flags: flags)
        case _ where shells.contains(name):
            if let c = args.firstIndex(where: { $0 == "-c" || ($0.hasPrefix("-") && $0.hasSuffix("c")) }) {
                return blockedReason(words[(c + 1)...].joined(separator: " "))
            }
        default: break
        }

        if wrappers.contains(name) {
            if name == "find", args.contains("-delete") { return "deletes files" }
            for i in words.indices { if let reason = blockedWords(Array(words[i...])) { return reason } }
        }
        return nil
    }

    private static func blockedGit(_ args: [String], flags: [Substring]) -> String? {
        guard let sub = args.first(where: { !$0.hasPrefix("-") }) else { return nil }
        switch sub {
        case "push" where args.contains(where: { $0 == "-f" || $0.hasPrefix("--force") || $0 == "--mirror" || $0 == "--delete" }):
            return "force-pushes"
        case "reset" where args.contains("--hard"): return "throws away local changes"
        case "clean" where flags.contains(where: { $0.contains("f") }): return "deletes untracked files"
        default: return nil
        }
    }
}
