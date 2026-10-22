import AppKit

/// Terminal app Claude sessions open in. Terminal and iTerm2 can be typed into, so prompts sent
/// from MyWorkDock arrive as real user prompts.
enum OpenIn: String, CaseIterable, Identifiable, Codable {
    case terminal, iTerm2 = "iterm2", warp, cmux, ghostty, kitty, alacritty, wezTerm = "wezterm"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm2: "iTerm2"
        case .warp: "Warp"
        case .cmux: "cmux"
        case .ghostty: "Ghostty"
        case .kitty: "kitty"
        case .alacritty: "Alacritty"
        case .wezTerm: "WezTerm"
        }
    }
    /// Every bundle id the app ships under (stable, preview and beta builds); the first installed one is used.
    var bundleIDs: [String] {
        switch self {
        case .terminal: ["com.apple.Terminal"]
        case .iTerm2: ["com.googlecode.iterm2"]
        case .warp: ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp-Beta", "dev.warp.Warp"]
        case .cmux: ["com.cmuxterm.app"]
        case .ghostty: ["com.mitchellh.ghostty", "com.mitchellh.ghostty.tip"]
        case .kitty: ["net.kovidgoyal.kitty"]
        case .alacritty: ["org.alacritty", "io.alacritty"]
        case .wezTerm: ["com.github.wez.wezterm"]
        }
    }
    var bundleID: String { bundleIDs[0] }
    var realPrompts: Bool { self == .terminal || self == .iTerm2 }
}

enum TerminalLauncher {
    struct Step: Equatable {
        var exe: String
        var args: [String]
    }

    static let warpPrefix = "mwd_resume_"

    /// Installed terminal apps; `installed(bundleID)` is injected by tests.
    static func detect(_ installed: (String) -> Bool = { appURL($0) != nil }) -> [OpenIn] {
        OpenIn.allCases.filter { app in app == .terminal || app.bundleIDs.contains(where: installed) }
    }

    static func appURL(_ bundleID: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// The installed copy of `app` (whichever of its bundle ids is present).
    static func appURL(_ app: OpenIn) -> URL? { app.bundleIDs.lazy.compactMap { appURL($0) }.first }

    /// cmux's command-line tool, inside its app bundle.
    static func cmuxCLI(_ appURL: URL?) -> String {
        (appURL ?? URL(fileURLWithPath: "/Applications/cmux.app")).appendingPathComponent("Contents/Resources/bin/cmux").path
    }

    private static func checkID(_ id: String) throws {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { throw AgentError("That session id isn't valid.") }
    }

    static func resumeCommand(cwd: String, id: String) throws -> String {
        try checkID(id)
        return "cd '\(cwd.replacingOccurrences(of: "'", with: "'\\''"))' && claude --resume \(id)"
    }

    private static var shell: String { ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh" }

    /// Ways to open the session, tried in order; Terminal is always the last resort.
    static func plan(_ app: OpenIn, cwd: String, id: String, command: String, cmux: String = cmuxCLI(nil)) -> [Step] {
        let quoted = TerminalLookup.appleScriptText(command)
        let terminal = Step(exe: "/usr/bin/osascript", args: ["-e", "tell application \"Terminal\"\nactivate\ndo script \"\(quoted)\"\nend tell"])
        let first: Step
        switch app {
        case .terminal: return [terminal]
        case .iTerm2:
            first = Step(exe: "/usr/bin/osascript", args: ["-e", "tell application \"iTerm2\"\nactivate\nset w to (create window with default profile)\ntell current session of w to write text \"\(quoted)\"\nend tell"])
        case .warp: first = Step(exe: "/usr/bin/open", args: ["warp://tab_config/\(warpStem(id))"])
        case .cmux:
            first = Step(exe: cmux, args: ["new-workspace", "--name", "Claude \(id.prefix(8))", "--cwd", cwd,
                                           "--command", "claude --resume \(id)", "--focus", "true"])
        case .ghostty: first = Step(exe: "/usr/bin/open", args: ["-na", "Ghostty", "--args", "--working-directory=\(cwd)", "-e", shell, "-lc", command])
        case .kitty: first = Step(exe: "/usr/bin/open", args: ["-na", "kitty", "--args", "--directory", cwd, shell, "-lc", command])
        case .alacritty: first = Step(exe: "/usr/bin/open", args: ["-na", "Alacritty", "--args", "--working-directory", cwd, "-e", shell, "-lc", command])
        case .wezTerm: first = Step(exe: "/usr/bin/open", args: ["-na", "WezTerm", "--args", "start", "--cwd", cwd, "--", shell, "-lc", command])
        }
        return [first, terminal]
    }

    static func warpStem(_ id: String) -> String { warpPrefix + String(id.prefix(8)) }

    private static func tomlString(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case _ where CharacterSet.controlCharacters.contains(c): out += String(format: "\\u%04X", c.value)
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    /// Writes a Warp tab config that opens `cwd` and runs `claude --resume <id>`; returns the stem
    /// `warp://tab_config/<stem>` opens. Removes MyWorkDock's older files; never the user's.
    @discardableResult
    static func writeWarpTabConfig(dir: URL, cwd: String, id: String) throws -> String {
        try checkID(id)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where f.lastPathComponent.hasPrefix(warpPrefix) && f.pathExtension == "toml" {
            let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if Date().timeIntervalSince(m) > 120 { try? fm.removeItem(at: f) }
        }
        let stem = warpStem(id)
        let text = """
        # Written by MyWorkDock to resume a Claude Code session. Safe to delete.
        name = \(tomlString("Claude \(id.prefix(8))"))

        [[panes]]
        id = "main"
        type = "terminal"
        directory = \(tomlString(cwd))
        commands = [\(tomlString("claude --resume \(id)"))]

        """
        try Data(text.utf8).write(to: dir.appendingPathComponent("\(stem).toml"))
        return stem
    }

    /// Opens the session in `app` (falling back to Terminal) and returns the app actually used.
    static func resume(cwd: String, id: String, in app: OpenIn) async throws -> OpenIn {
        guard FileManager.default.fileExists(atPath: cwd) else { throw AgentError("The project folder no longer exists: \(cwd)") }
        let app = detect().contains(app) ? app : .terminal // never script an app that isn't installed
        let command = try resumeCommand(cwd: cwd, id: id)
        if app == .warp {
            try writeWarpTabConfig(dir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warp/tab_configs"), cwd: cwd, id: id)
            try await Task.sleep(nanoseconds: 700_000_000) // Warp picks new tab configs up from disk
        }
        var cli = cmuxCLI(nil)
        if app == .cmux, let url = appURL(.cmux) {
            cli = cmuxCLI(url)
            // Launch (or bring forward) cmux, then wait for its socket: new-workspace needs the app running.
            _ = await ProcessRunner.run("/usr/bin/open", [url.path], timeout: 10)
            for _ in 0..<20 {
                if await ProcessRunner.run(cli, ["ping"], timeout: 2).ok { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        var errors: [String] = []
        for (i, step) in plan(app, cwd: cwd, id: id, command: command, cmux: cli).enumerated() {
            let r = await ProcessRunner.run(step.exe, step.args, timeout: 10)
            if r.ok { return i == 0 ? app : .terminal }
            if r.err.contains("-1743") { errors.append("Allow MyWorkDock to control \(app.name) in System Settings › Privacy & Security › Automation.") }
            else { errors.append("\((step.exe as NSString).lastPathComponent): \(r.firstLine)") }
        }
        throw AgentError(errors.joined(separator: " "))
    }
}
