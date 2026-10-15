import Foundation

struct ProcessResult: Sendable {
    var status: Int32
    var out: String
    var err: String
    var timedOut = false

    var ok: Bool { status == 0 && !timedOut }
    /// stdout, else stderr: what a command-line tool "said".
    var text: String { (out.isEmpty ? err : out).trimmingCharacters(in: .whitespacesAndNewlines) }
    /// First line of whatever it said, for one-line messages.
    var firstLine: String { text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "" }

    static func failed(_ why: String) -> ProcessResult { ProcessResult(status: -1, out: "", err: why) }
}

/// The only way the app shells out: async, with a timeout, never on the main thread.
enum ProcessRunner {
    typealias Runner = @Sendable (_ exe: String, _ args: [String]) async -> ProcessResult

    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 20) async -> ProcessResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runBlocking(exe, args, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ exe: String, _ args: [String], timeout: TimeInterval) -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .failed("\(exe): \(error.localizedDescription)") }

        // Drain both pipes while the process runs, otherwise a chatty tool fills the pipe and blocks forever.
        final class Box: @unchecked Sendable { var out = Data(), err = Data(), timedOut = false }
        let box = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { box.out = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { box.err = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let killer = DispatchWorkItem { if p.isRunning { box.timedOut = true; p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        group.wait()
        return ProcessResult(status: p.terminationStatus, out: String(decoding: box.out, as: UTF8.self),
                             err: String(decoding: box.err, as: UTF8.self), timedOut: box.timedOut)
    }

    /// Starts a long-running tool (an emulator) and does not wait for it. Returns false if it could not launch.
    static func spawn(_ exe: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run(); return true } catch { return false }
    }

    /// A GUI app inherits a bare PATH; give child tools the usual developer directories.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        env["PATH"] = (path + PathResolver.extraDirs.filter { !path.contains($0) }).joined(separator: ":")
        // A GUI app has no LANG, so a Python tool (claudex) would default to ascii and crash on its own box-drawing output.
        env["PYTHONIOENCODING"] = "utf-8"
        return env
    }()
}

/// Finds `adb`, `emulator`, `claudex`, ...: known developer directories first, then the user's login shell.
enum PathResolver {
    static let extraDirs: [String] = {
        let home = NSHomeDirectory()
        let env = ProcessInfo.processInfo.environment
        let sdk = [env["ANDROID_HOME"], env["ANDROID_SDK_ROOT"], home + "/Library/Android/sdk"].compactMap { $0 }
        return sdk.flatMap { [$0 + "/platform-tools", $0 + "/emulator"] } + [
            "/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.claude/local",
            home + "/.npm-global/bin", home + "/.bun/bin", home + "/.volta/bin",
        ]
    }()

    nonisolated(unsafe) private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    private static func cached(_ name: String) -> String?? { lock.withLock { cache[name] } }
    private static func remember(_ name: String, _ path: String?) { lock.withLock { cache[name] = .some(path) } }

    /// Drops a remembered result, so a tool installed since the last miss is found again.
    static func forget(_ name: String) { lock.withLock { cache[name] = nil } }

    static func find(_ name: String) async -> String? {
        if let hit = cached(name) { return hit }
        let found = await lookup(name)
        remember(name, found)
        return found
    }

    private static func lookup(_ name: String) async -> String? {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + extraDirs {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // ponytail: spawns an interactive login shell once per missing tool; fine at this call rate.
        let shell = await ProcessRunner.run("/bin/zsh", ["-ilc", "command -v \(name)"], timeout: 6)
        let line = shell.out.split(whereSeparator: \.isNewline).map(String.init).last { $0.hasPrefix("/") }
        return line.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }
}
