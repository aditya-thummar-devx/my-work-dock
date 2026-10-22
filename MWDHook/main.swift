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

func run(_ args: Args, _ raw: Data) -> (String, Int32) {
    let payload = (try? JSONDecoder().decode(JSONValue.self, from: raw)) ?? .string(String(decoding: raw, as: UTF8.self))
    let term = ProcessInfo.processInfo.environment["TERM_PROGRAM"].flatMap { $0.isEmpty ? nil : $0 }
    let msg = HookMessage(v: HookWire.version, id: UUID().uuidString, agent: args.agent, event: args.event,
                          cwd: FileManager.default.currentDirectoryPath, pid: getppid(), payload: payload,
                          expects_reply: args.wait, term: term)
    guard let fd = SocketIO.connect(HookWire.socketPath) else { return ("", 0) }
    defer { close(fd) }
    guard let frame = try? HookWire.encode(msg), SocketIO.writeAll(fd, frame), args.wait else { return ("", 0) }
    var tv = timeval(tv_sec: Int(args.timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    guard let body = SocketIO.readFrame(fd),
          let reply = try? JSONDecoder().decode(HookReply.self, from: body), reply.id == msg.id else { return ("", 0) }
    return (reply.stdout, reply.exit_code)
}

signal(SIGPIPE, SIG_IGN)
let args = parseArgs(Array(CommandLine.arguments.dropFirst()))
let input = FileHandle.standardInput.readDataToEndOfFile()
let (out, code) = run(args, input)
if !out.isEmpty { FileHandle.standardOutput.write(Data(out.utf8)) }
exit(code)
