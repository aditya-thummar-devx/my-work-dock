import Foundation
import Observation

/// Lets Claude Code add todos: `mwd-mcp` (an MCP server shipped inside the app) sends each `add_todo` call to this socket.
/// Runs while Notes › TODO is on. The banner in the TODO tab registers the server with Claude Code.
@MainActor @Observable
final class TodoBridge {
    private(set) var status: ClaudeMCPInstaller.Status = .notInstalled
    private(set) var installing = false
    private(set) var error: String?
    /// "Not now" on the banner; saved.
    private(set) var dismissed: Bool

    @ObservationIgnored private let notes: NotesStore
    @ObservationIgnored private let installer: ClaudeMCPInstaller?
    @ObservationIgnored private var server: TodoServer?
    private static let dismissedKey = "todoMCPBannerDismissed"

    init(notes: NotesStore, installer: ClaudeMCPInstaller?) {
        self.notes = notes
        self.installer = installer
        dismissed = installer == nil || UserDefaults.standard.bool(forKey: Self.dismissedKey)
        refresh()
    }

    static func live(notes: NotesStore) -> TodoBridge { TodoBridge(notes: notes, installer: .live()) }
    /// Designs / snapshots: no socket, no banner.
    static func sample(notes: NotesStore) -> TodoBridge { TodoBridge(notes: notes, installer: nil) }

    var showsBanner: Bool { !dismissed && status != .installed }

    func start() {
        guard let installer, server == nil else { return }
        let s = TodoServer { [weak self] in self?.handle($0) ?? TodoReply(v: HookWire.version, ok: false, error: "MyWorkDock is shutting down.") }
        do {
            try s.start()
            server = s
        } catch {
            NSLog("MyWorkDock: todo socket not started: \(error)")
        }
        // Keep the stable copy Claude Code runs current (app updates, moved bundles) once the user has connected it.
        if installer.status() != .notInstalled { try? installer.deploy() }
        refresh()
    }

    func stop() {
        server?.stop()
        server = nil
    }

    func refresh() { status = installer?.status() ?? .notInstalled }

    func connect() async {
        guard let installer, !installing else { return }
        installing = true
        defer { installing = false }
        do {
            try await installer.install()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func dismiss() {
        dismissed = true
        UserDefaults.standard.set(true, forKey: Self.dismissedKey)
    }

    func handle(_ req: TodoRequest) -> TodoReply {
        guard req.v == HookWire.version else {
            return TodoReply(v: HookWire.version, ok: false, error: "MyWorkDock and its Claude Code server are different versions. Start a new Claude session.")
        }
        guard let todo = notes.add(req.title, tag: req.tag.map(NotesStore.cleanTag)) else {
            return TodoReply(v: HookWire.version, ok: false, error: "The todo title is empty.")
        }
        return TodoReply(v: HookWire.version, ok: true, id: todo.id, title: todo.title, tag: todo.tag,
                         error: notes.saveError.map { "Added, but saving to disk failed: \($0)" })
    }
}

/// Registers `mwd-mcp` with Claude Code (user scope) through the `claude` CLI; never writes Claude's files itself.
struct ClaudeMCPInstaller {
    static let name = "myworkdock"

    /// Where the `claude` CLI keeps user-scope MCP servers; read only, for the status.
    var claudeConfig: URL
    /// The server shipped inside the app bundle.
    var bundledServer: URL
    /// Stable copy Claude Code runs, so moving or updating the app never breaks it.
    var binDir: URL

    enum Status: Equatable { case notInstalled, installed, stale }

    enum InstallError: LocalizedError {
        case noCLI(String), failed(String)
        var errorDescription: String? {
            switch self {
            case .noCLI(let cmd): "Claude Code's `claude` command wasn't found. Run: \(cmd)"
            case .failed(let why): "Couldn't connect to Claude Code: \(why)"
            }
        }
    }

    static func live() -> ClaudeMCPInstaller {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyWorkDock")
        return ClaudeMCPInstaller(
            claudeConfig: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"),
            bundledServer: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mwd-mcp"),
            binDir: support.appendingPathComponent("bin"))
    }

    var deployedServer: URL { binDir.appendingPathComponent("mwd-mcp") }

    var addArguments: [String] { ["mcp", "add", "--scope", "user", Self.name, "--", deployedServer.path] }

    /// ponytail: reads ~/.claude.json only; a custom CLAUDE_CONFIG_DIR shows "not connected" (Connect still works).
    func status() -> Status {
        guard let data = try? Data(contentsOf: claudeConfig),
              let cfg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entry = (cfg["mcpServers"] as? [String: Any])?[Self.name] as? [String: Any] else { return .notInstalled }
        let current = entry["command"] as? String == deployedServer.path && FileManager.default.isExecutableFile(atPath: deployedServer.path)
        return current ? .installed : .stale
    }

    func deploy() throws { try ClaudeHookInstaller.deploy(bundledServer, to: deployedServer) }

    func install() async throws {
        try deploy()
        guard let claude = await PathResolver.find("claude") else {
            throw InstallError.noCLI((["claude"] + addArguments.dropLast() + ["\"\(deployedServer.path)\""]).joined(separator: " "))
        }
        // An older entry (another path) must go first: `add` refuses a name that exists.
        _ = await ProcessRunner.run(claude, ["mcp", "remove", "--scope", "user", Self.name])
        let r = await ProcessRunner.run(claude, addArguments)
        guard r.ok else { throw InstallError.failed(r.firstLine.isEmpty ? "exit \(r.status)" : r.firstLine) }
    }
}

/// One request per connection: read a `TodoRequest`, answer with a `TodoReply`, close.
final class TodoServer: @unchecked Sendable {
    private let path: String
    private let handle: @MainActor (TodoRequest) -> TodoReply
    private var listenFD: Int32 = -1

    init(path: String = TodoWire.socketPath, handle: @escaping @MainActor (TodoRequest) -> TodoReply) {
        self.path = path
        self.handle = handle
    }

    func start() throws {
        let fd = try SocketIO.listen(path)
        listenFD = fd
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    func stop() {
        // shutdown wakes the thread blocked in accept(); close alone may not.
        if listenFD >= 0 { shutdown(listenFD, SHUT_RDWR); close(listenFD); listenFD = -1 }
        unlink(path)
    }

    private func acceptLoop(_ lfd: Int32) {
        while true {
            let c = accept(lfd, nil, nil)
            if c < 0 {
                if [EINTR, EMFILE, ENFILE, ECONNABORTED].contains(errno) { usleep(100_000); continue }
                return // listener closed
            }
            Thread.detachNewThread { [self] in serve(c) }
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let reply: TodoReply
        if let body = SocketIO.readFrame(fd), let req = try? JSONDecoder().decode(TodoRequest.self, from: body) {
            let handle = self.handle
            reply = DispatchQueue.main.sync { MainActor.assumeIsolated { handle(req) } }
        } else {
            reply = TodoReply(v: HookWire.version, ok: false, error: "MyWorkDock couldn't read the request.")
        }
        if let data = try? HookWire.encode(reply) { _ = SocketIO.writeAll(fd, data) }
    }
}
