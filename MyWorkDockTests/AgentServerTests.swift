import XCTest
@testable import MyWorkDock

/// End to end: the real `mwd-hook` binary against the real socket server.
@MainActor
final class AgentServerTests: XCTestCase {
    private var dir: URL!
    private var sock: String { dir.appendingPathComponent("a.sock").path }

    override func setUp() async throws {
        dir = URL(fileURLWithPath: "/tmp").appendingPathComponent("mwd-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private var hookURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mwd-hook")
    }

    private func spawn(_ event: String, _ payload: String, wait: Bool = true) throws -> (Process, Pipe) {
        let p = Process()
        p.executableURL = hookURL
        p.arguments = ["--agent", "claude", "--event", event] + (wait ? ["--wait"] : [])
        p.environment = [HookWire.socketEnv: sock]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        return (p, output)
    }

    private func until(_ cond: () -> Bool) async {
        for _ in 0..<200 where !cond() { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    private func finish(_ p: Process, _ out: Pipe) async -> (String, Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (String(decoding: data, as: UTF8.self), p.terminationStatus))
            }
        }
    }

    func testApproveFromTheAppReachesTheAgent() async throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hookURL.path), "mwd-hook is embedded")
        let core = AgentCore(ttyLookup: { _ in nil })
        let server = AgentServer(path: sock, core: core)
        try server.start()
        defer { server.stop() }
        let (p, out) = try spawn("PermissionRequest", #"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}"#)
        await until { !core.pending.isEmpty }
        XCTAssertEqual(core.pending.count, 1)
        core.decide(core.pending[0].id, .allow(always: false))
        let (stdout, code) = await finish(p, out)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(stdout.contains(#""behavior":"allow""#), stdout)
    }

    func testKilledHookClearsThePendingCard() async throws {
        let core = AgentCore(ttyLookup: { _ in nil })
        let server = AgentServer(path: sock, core: core)
        try server.start()
        defer { server.stop() }
        let (p, _) = try spawn("PermissionRequest", #"{"session_id":"s1","tool_name":"Bash","tool_input":{}}"#)
        await until { !core.pending.isEmpty }
        p.terminate()
        await until { core.pending.isEmpty }
        XCTAssertTrue(core.pending.isEmpty)
    }

    func testWakeHookExits2WithThePrompt() async throws {
        let core = AgentCore(ttyLookup: { _ in nil })
        let server = AgentServer(path: sock, core: core)
        try server.start()
        defer { server.stop() }
        let (p, out) = try spawn("Wake", #"{"session_id":"s1"}"#)
        await until { core.liveSessions().first?.reachable == true }
        XCTAssertEqual(try core.sendPrompt("claude:s1", "write docs"), .delivered)
        let (stdout, code) = await finish(p, out)
        XCTAssertEqual(code, 2)
        XCTAssertTrue(stdout.contains("write docs"))
    }

    func testSecondServerDoesNotStealTheSocket() throws {
        let core = AgentCore(ttyLookup: { _ in nil })
        let a = AgentServer(path: sock, core: core)
        try a.start()
        defer { a.stop() }
        XCTAssertThrowsError(try AgentServer(path: sock, core: core).start())
        var st = stat()
        XCTAssertEqual(stat(sock, &st), 0)
        XCTAssertEqual(st.st_mode & 0o777, 0o600, "socket is private")
    }

    func testNoAppMeansSilentImmediateExit() async throws {
        let (p, out) = try spawn("PermissionRequest", "{}")
        let (stdout, code) = await finish(p, out)
        XCTAssertEqual(stdout, "")
        XCTAssertEqual(code, 0)
    }
}
