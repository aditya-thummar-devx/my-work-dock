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
