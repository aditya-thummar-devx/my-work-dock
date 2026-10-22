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
        let fd: Int32
        do { fd = try SocketIO.listen(path) }
        catch SocketIO.ListenError.inUse { throw StartError.alreadyRunning }
        catch SocketIO.ListenError.system(let s) { throw StartError.system(s) }
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
            var on: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            Thread.detachNewThread { [self] in serve(c) }
        }
    }

    /// One hook connection: read its message, answer now or hold it until a decision or hang-up.
    private func serve(_ fd: Int32) {
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard let body = SocketIO.readFrame(fd), let msg = try? JSONDecoder().decode(HookMessage.self, from: body) else { close(fd); return }

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
            if let reply, let data = try? HookWire.encode(reply) { _ = SocketIO.writeAll(fd, data) }
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
}
