import Foundation

/// Accepts `mwd-hook` connections on a private Unix socket and routes them through `AgentCore`.
/// A held request keeps its connection open; when the hook hangs up first, the request is cancelled.
final class AgentServer: @unchecked Sendable {
    private let path: String
    private let core: AgentCore
    private var listenFD: Int32 = -1

    init(path: String = HookWire.socketPath, core: AgentCore) {
        self.path = path
        self.core = core
    }

    enum StartError: Error, LocalizedError {
        case alreadyRunning, system(String)
        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "Another MyWorkDock is already listening for agents."
            case .system(let s): s
            }
        }
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        // A socket that still answers belongs to a running copy; only clear dead ones.
        if let fd = Self.connect(path) { close(fd); throw StartError.alreadyRunning }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw StartError.system("socket: \(errno)") }
        var addr = Self.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 32) == 0 else { close(fd); throw StartError.system("bind/listen: \(errno)") }
        chmod(path, 0o600)
        listenFD = fd
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }

    private func acceptLoop(_ lfd: Int32) {
        while true {
            let c = accept(lfd, nil, nil)
            if c < 0 {
                if errno == EINTR || errno == EMFILE || errno == ENFILE { usleep(100_000); continue }
                return // listener closed
            }
            var on: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            Thread.detachNewThread { [self] in serve(c) }
        }
    }

    /// One hook connection: read its message, answer now or hold it until a decision or hang-up.
    private func serve(_ fd: Int32) {
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard let header = Self.readExactly(fd, 4), let len = HookWire.length(header), let body = Self.readExactly(fd, len),
              let msg = try? JSONDecoder().decode(HookMessage.self, from: body) else { close(fd); return }

        let conn = Connection(fd: fd)
        let core = self.core
        let held = DispatchSemaphore(value: 0)
        var wait = false
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let result = core.handle(msg) { decision in
                    conn.finish(with: core.reply(msg, decision))
                }
                switch result {
                case .reply(let r):
                    if msg.expects_reply { conn.finish(with: r) } else { conn.finish(with: nil) }
                case .wait:
                    wait = true
                }
            }
            held.signal()
        }
        held.wait()
        guard wait else { return }
        // Held: watch for the hook going away (it never sends a second frame).
        if conn.waitForHangUp() {
            DispatchQueue.main.async { MainActor.assumeIsolated { core.cancel(msg.id) } }
        }
    }

    /// Closes exactly once, whichever of "decision" or "hang-up" comes first.
    private final class Connection: @unchecked Sendable {
        private let fd: Int32
        private let lock = NSLock()
        private var done = false

        init(fd: Int32) { self.fd = fd }

        func finish(with reply: HookReply?) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true
            if let reply, let data = try? HookWire.encode(reply) { _ = AgentServer.writeAll(fd, data) }
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }

        /// True when the peer hung up before a decision; false when `finish` closed it.
        func waitForHangUp() -> Bool {
            var tv = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var byte: UInt8 = 0
            while true {
                let n = recv(fd, &byte, 1, MSG_PEEK)
                if n > 0 { usleep(50_000); continue }
                if n < 0 && errno == EINTR { continue }
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                close(fd)
                return true
            }
        }
    }

    // MARK: socket helpers

    static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: addr.sun_path) - 1))
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = b } }
        return addr
    }

    static func connect(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = address(path)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
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
}
