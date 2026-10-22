import Foundation

// mwd-hook: forwards an agent hook payload to MyWorkDock and relays the reply.
// It must never block or break the agent: every failure exits 0 with no output.

struct Args {
    var agent = "unknown", event = "unknown", wait = false, timeout: TimeInterval = 600
}

func parseArgs(_ argv: [String]) -> Args {
    var a = Args()
    var it = argv.makeIterator()
    while let flag = it.next() {
        switch flag {
        case "--agent": a.agent = it.next() ?? a.agent
        case "--event": a.event = it.next() ?? a.event
        case "--wait": a.wait = true
        case "--timeout-secs": a.timeout = it.next().flatMap(TimeInterval.init) ?? a.timeout
        default: break
        }
    }
    return a
}

/// Connects to the app's socket, refusing one that another user created.
func connectSocket(_ path: String) -> Int32? {
    var st = stat()
    guard lstat(path, &st) == 0, st.st_uid == getuid() else { return nil }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        for (i, b) in bytes.enumerated() { raw[i] = b }
    }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if ok != 0 { close(fd); return nil }
    return fd
}

func writeAll(_ fd: Int32, _ data: Data) -> Bool {
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

func readExactly(_ fd: Int32, _ count: Int) -> Data? {
    var buf = [UInt8](repeating: 0, count: count)
    var off = 0
    while off < count {
        let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress! + off, count - off) }
        if n <= 0 { return nil }
        off += n
    }
    return Data(buf)
}

func run(_ args: Args, _ raw: Data) -> (String, Int32) {
    let payload = (try? JSONDecoder().decode(JSONValue.self, from: raw)) ?? .string(String(decoding: raw, as: UTF8.self))
    let term = ProcessInfo.processInfo.environment["TERM_PROGRAM"].flatMap { $0.isEmpty ? nil : $0 }
    let msg = HookMessage(v: HookWire.version, id: UUID().uuidString, agent: args.agent, event: args.event,
                          cwd: FileManager.default.currentDirectoryPath, pid: getppid(), payload: payload,
                          expects_reply: args.wait, term: term)
    guard let fd = connectSocket(HookWire.socketPath) else { return ("", 0) }
    defer { close(fd) }
    guard let frame = try? HookWire.encode(msg), writeAll(fd, frame), args.wait else { return ("", 0) }
    var tv = timeval(tv_sec: Int(args.timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    guard let header = readExactly(fd, 4), let len = HookWire.length(header), let body = readExactly(fd, len),
          let reply = try? JSONDecoder().decode(HookReply.self, from: body), reply.id == msg.id else { return ("", 0) }
    return (reply.stdout, reply.exit_code)
}

signal(SIGPIPE, SIG_IGN)
let args = parseArgs(Array(CommandLine.arguments.dropFirst()))
let input = FileHandle.standardInput.readDataToEndOfFile()
let (out, code) = run(args, input)
if !out.isEmpty { FileHandle.standardOutput.write(Data(out.utf8)) }
exit(code)
