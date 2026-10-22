import XCTest
@testable import MyWorkDock

/// End to end: the real `mwd-mcp` binary, speaking MCP on stdio, against the real todo socket.
@MainActor
final class TodoBridgeTests: XCTestCase {
    private var dir: URL!
    private var sock: String { dir.appendingPathComponent("t.sock").path }

    override func setUp() async throws {
        // /tmp, not the long temporary directory: socket paths must fit sun_path.
        dir = URL(fileURLWithPath: "/tmp").appendingPathComponent("mwd-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    private var serverURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mwd-mcp") }

    /// Feeds `lines` to mwd-mcp and returns every JSON-RPC message it wrote, keyed by id.
    private func run(_ lines: [String]) async throws -> [String: [String: Any]] {
        let p = Process()
        p.executableURL = serverURL
        p.environment = [TodoWire.socketEnv: sock]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        input.fileHandleForWriting.write(Data(lines.joined(separator: "\n").utf8 + [0x0A]))
        try input.fileHandleForWriting.close()
        let data: Data = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let d = output.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: d)
            }
        }
        var out: [String: [String: Any]] = [:]
        for line in data.split(separator: 0x0A) {
            let msg = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            out["\(msg["id"] ?? "null")"] = msg
        }
        return out
    }

    private func call(_ id: Int, _ args: String) -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"add_todo","arguments":\#(args)}}"#
    }

    private func text(_ msg: [String: Any]?) -> (String, Bool) {
        let result = msg?["result"] as? [String: Any]
        let content = (result?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        return (content, result?["isError"] as? Bool ?? true)
    }

    func testClaudeCodeAddsATodoToTheRunningApp() async throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: serverURL.path), "mwd-mcp is embedded")
        let notes = NotesStore(url: nil)
        let bridge = TodoBridge.sample(notes: notes)
        let server = TodoServer(path: sock) { bridge.handle($0) }
        try server.start()
        defer { server.stop() }

        let out = try await run([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            call(3, #"{"title":"Ship the build #release"}"#),
            call(4, ##"{"title":"Write docs","tag":"#Docs Team"}"##),
            call(5, #"{"title":"   "}"#),
        ])

        XCTAssertEqual((out["1"]?["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual(out.count, 5, "the notification gets no answer")
        let tools = (out["2"]?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.map { $0["name"] as? String }, ["add_todo"])

        XCTAssertEqual(text(out["3"]).1, false)
        XCTAssertTrue(text(out["3"]).0.contains("Ship the build (#release)"), text(out["3"]).0)
        XCTAssertEqual(text(out["5"]).1, true, "blank title is refused")
        XCTAssertEqual(notes.todos.map(\.title), ["Write docs", "Ship the build"])
        XCTAssertEqual(notes.todos.map(\.tag), ["docs-team", "release"])
    }

    func testNoAppIsAToolErrorNotACrash() async throws {
        let out = try await run([call(1, #"{"title":"x"}"#), #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#])
        let (msg, isError) = text(out["1"])
        XCTAssertTrue(isError)
        XCTAssertTrue(msg.contains("isn't running"), msg)
        XCTAssertNotNil(out["2"]?["result"], "still serving after the failure")
    }

    func testOldServerVersionIsRefusedNotMisread() {
        let notes = NotesStore(url: nil)
        let r = TodoBridge.sample(notes: notes).handle(TodoRequest(v: HookWire.version + 1, title: "x"))
        XCTAssertFalse(r.ok)
        XCTAssertTrue(notes.todos.isEmpty)
    }

    // MARK: installer status

    private func installer() -> ClaudeMCPInstaller {
        ClaudeMCPInstaller(claudeConfig: dir.appendingPathComponent(".claude.json"),
                           bundledServer: dir.appendingPathComponent("build/mwd-mcp"),
                           binDir: dir.appendingPathComponent("bin"))
    }

    private func writeConfig(command: String) throws {
        let cfg: [String: Any] = ["mcpServers": ["myworkdock": ["type": "stdio", "command": command, "args": []], "other": [:]]]
        try JSONSerialization.data(withJSONObject: cfg).write(to: dir.appendingPathComponent(".claude.json"))
    }

    func testStatusFollowsClaudesConfigAndTheDeployedCopy() throws {
        let i = installer()
        XCTAssertEqual(i.status(), .notInstalled, "no config file")
        try writeConfig(command: i.deployedServer.path)
        XCTAssertEqual(i.status(), .stale, "registered, but nothing deployed yet")

        let bundled = dir.appendingPathComponent("build/mwd-mcp")
        try FileManager.default.createDirectory(at: bundled.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: bundled)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
        try i.deploy()
        XCTAssertEqual(i.status(), .installed)

        try writeConfig(command: "/Applications/Old.app/Contents/MacOS/mwd-mcp")
        XCTAssertEqual(i.status(), .stale, "points somewhere else")
        XCTAssertEqual(i.addArguments, ["mcp", "add", "--scope", "user", "myworkdock", "--", i.deployedServer.path])
    }
}
