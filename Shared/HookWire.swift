import Foundation

/// Wire protocol between `mwd-hook` (run by the agent) and the app: a 4-byte big-endian length
/// followed by UTF-8 JSON. Same shape as Peekaboo's protocol v1.
enum HookWire {
    static let version = 1
    static let maxFrame = 8 * 1024 * 1024
    /// Overrides the socket path (tests).
    static let socketEnv = "MWD_SOCKET"

    static var socketPath: String {
        if let p = ProcessInfo.processInfo.environment[socketEnv], !p.isEmpty { return p }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MyWorkDock/agents.sock").path
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maxFrame else { throw WireError.tooLarge }
        var len = UInt32(body.count).bigEndian
        return Data(bytes: &len, count: 4) + body
    }

    /// Length from a 4-byte header, or nil when it is over the limit.
    static func length(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let n = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        return n <= maxFrame ? n : nil
    }

    enum WireError: Error { case tooLarge, closed, malformed }
}

/// Any JSON value (hook payloads are agent-defined).
enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

struct HookMessage: Codable, Equatable {
    var v: Int
    var id: String
    var agent: String
    var event: String
    var cwd: String?
    var pid: Int32?
    var payload: JSONValue
    var expects_reply: Bool
    /// The agent's `TERM_PROGRAM`, when known.
    var term: String?
}

struct HookReply: Codable, Equatable {
    var v: Int
    var id: String
    var stdout: String
    var exit_code: Int32

    /// Makes the agent behave as if no hook ran.
    static func passthrough(_ id: String) -> HookReply { HookReply(v: HookWire.version, id: id, stdout: "", exit_code: 0) }
}

/// `mwd-mcp` (Claude Code's MCP server) asks the app to add a todo over a socket of its own, framed like `HookWire`.
enum TodoWire {
    /// Overrides the socket path (tests).
    static let socketEnv = "MWD_TODO_SOCKET"

    static var socketPath: String {
        if let p = ProcessInfo.processInfo.environment[socketEnv], !p.isEmpty { return p }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MyWorkDock/todos.sock").path
    }
}

struct TodoRequest: Codable, Equatable {
    var v: Int
    var title: String
    var tag: String?
}

struct TodoReply: Codable, Equatable {
    var v: Int
    var ok: Bool
    var id: Int?
    var title: String?
    var tag: String?
    var error: String?
}

/// Blocking Unix-socket helpers shared by the app's servers and the bundled tools.
enum SocketIO {
    enum ListenError: Error { case inUse, system(String) }

    /// nil when `path` doesn't fit `sun_path` (a truncated path would name a different socket).
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = b } }
        return addr
    }

    /// Connects to `path`, refusing a socket that another user created.
    static func connect(_ path: String) -> Int32? {
        var st = stat()
        guard var addr = address(path), lstat(path, &st) == 0, st.st_uid == getuid() else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        return fd
    }

    /// A private (0600) listening socket at `path`, in a 0700 directory. A socket that still answers belongs to a
    /// running copy (`inUse`); dead ones are cleared.
    static func listen(_ path: String) throws -> Int32 {
        guard var addr = address(path) else { throw ListenError.system("socket path too long: \(path)") }
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if let fd = connect(path) { close(fd); throw ListenError.inUse }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ListenError.system("socket: \(errno)") }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 32) == 0 else { close(fd); throw ListenError.system("bind/listen: \(errno)") }
        chmod(path, 0o600)
        return fd
    }

    static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var buf = [UInt8](repeating: 0, count: count)
        var off = 0
        while off < count {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress! + off, count - off) }
            if n <= 0 { return nil }
            off += n
        }
        return Data(buf)
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    /// The body of one length-prefixed frame; nil on hang-up, timeout or an oversized header.
    static func readFrame(_ fd: Int32) -> Data? {
        guard let header = readExactly(fd, 4), let len = HookWire.length(header) else { return nil }
        return readExactly(fd, len)
    }
}
