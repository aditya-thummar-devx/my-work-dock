import Foundation

// mwd-mcp: the MCP server Claude Code runs (stdio, newline-delimited JSON-RPC 2.0). Its one tool, add_todo, asks the
// running MyWorkDock to add a todo over the app's todo socket. Ships inside the app, so OTA updates replace it.
// Failures are tool results with isError, never a crash: the Claude session keeps going.

let addTodoTool: [String: Any] = [
    "name": "add_todo",
    "title": "Add todo",
    "description": """
        Add a todo to the TODO list in MyWorkDock, the user's macOS notch app. Use it when the user asks to add, note or \
        remember a todo or task. One call per todo. A #tag in the title, or the tag argument, files the todo under that tag.
        """,
    "inputSchema": [
        "type": "object",
        "properties": [
            "title": ["type": "string", "description": "The todo text, short. May contain a #tag."],
            "tag": ["type": "string", "description": "Optional tag name without #, e.g. \"release\". A #tag in the title wins."],
        ],
        "required": ["title"],
    ],
]

func send(_ obj: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func reply(_ id: Any, result: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": result]) }

func reply(_ id: Any, error code: Int, _ message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

/// One round trip to the app. Returns the tool's text and whether it is an error.
func addTodo(title: String, tag: String?) -> (String, Bool) {
    guard let fd = SocketIO.connect(TodoWire.socketPath) else {
        return ("MyWorkDock isn't running, or its Notes › TODO tab is switched off. Open MyWorkDock and try again.", true)
    }
    defer { close(fd) }
    var tv = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    guard let frame = try? HookWire.encode(TodoRequest(v: HookWire.version, title: title, tag: tag)), SocketIO.writeAll(fd, frame),
          let body = SocketIO.readFrame(fd), let r = try? JSONDecoder().decode(TodoReply.self, from: body) else {
        return ("MyWorkDock didn't answer. Try again.", true)
    }
    guard r.ok, let id = r.id else { return (r.error ?? "MyWorkDock couldn't add the todo.", true) }
    var text = "Added todo #\(id) to MyWorkDock: \(r.title ?? title)"
    if let t = r.tag, !t.isEmpty { text += " (#\(t))" }
    if let warning = r.error { text += ". \(warning)" }
    return (text, false)
}

func handle(_ msg: [String: Any]) {
    // Notifications (no id) and responses need no answer.
    guard let method = msg["method"] as? String, let id = msg["id"], !(id is NSNull) else { return }
    let params = msg["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        reply(id, result: [
            "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "myworkdock", "version": "\(HookWire.version)"],
        ])
    case "ping":
        reply(id, result: [:])
    case "tools/list":
        reply(id, result: ["tools": [addTodoTool]])
    case "tools/call":
        guard params["name"] as? String == "add_todo" else { return reply(id, error: -32602, "Unknown tool: \(params["name"] ?? "")") }
        let args = params["arguments"] as? [String: Any] ?? [:]
        let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = (args["tag"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let (text, isError) = title.isEmpty ? ("A todo title is required.", true) : addTodo(title: title, tag: tag)
        reply(id, result: ["content": [["type": "text", "text": text]], "isError": isError])
    default:
        reply(id, error: -32601, "Method not found: \(method)")
    }
}

signal(SIGPIPE, SIG_IGN)
while let line = readLine() {
    guard !line.allSatisfy(\.isWhitespace) else { continue }
    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)), let msg = obj as? [String: Any] else {
        reply(NSNull(), error: -32700, "Parse error")
        continue
    }
    handle(msg)
}
