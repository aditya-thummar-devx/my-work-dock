import Darwin
import Foundation

/// A shell command that streams its output while it runs and can be stopped as a whole tree.
/// `ProcessRunner` only returns at the end, so a long-running command (a dev server) needs this instead.
final class StreamingProcess: @unchecked Sendable {
    private let pid: pid_t
    private let lock = NSLock()
    private var exit: Int32?
    private var exitedAt = Date.distantFuture
    private var done = false

    private init(pid: pid_t) { self.pid = pid }

    /// Runs `command` with `/bin/zsh -lc` in `folder`, stdout and stderr on one stream, no stdin.
    /// `onOutput` gets chunks (at most ~20 a second); `onExit` comes last, on a background thread, once the output ended.
    /// nil when it could not start.
    static func launch(_ command: String, in folder: URL,
                       onOutput: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (Int32) -> Void) -> StreamingProcess? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        // Close-on-exec: only the dup2'd copies reach the child.
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, folder.path)

        // Its own process group, so stop() reaches everything the command started.
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        var argv: [UnsafeMutablePointer<CChar>?] = []
        for arg in ["zsh", "-lc", command] { argv.append(strdup(arg)) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in ProcessRunner.environment { envp.append(strdup("\(key)=\(value)")) }
        envp.append(nil)
        defer { for p in argv + envp { free(p) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/zsh", &actions, &attr, argv, envp)
        close(fds[1])
        guard rc == 0 else { close(fds[0]); return nil }

        let process = StreamingProcess(pid: pid)
        let readFD = fds[0]
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            // Exited normally: its code. Killed by a signal: 128 + the signal, as a shell reports it.
            let code = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            process.lock.withLock { process.exit = code; process.exitedAt = Date() }
            exited.signal()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            process.read(readFD, onOutput: onOutput)
            // The pipe can close before the exit status is in (a fast command): wait for it.
            exited.wait()
            let code = process.lock.withLock { () -> Int32 in process.done = true; return process.exit ?? -1 }
            onExit(code)
        }
        return process
    }

    /// Reads until the pipe closes. A backgrounded grandchild can keep it open after the command itself is gone, so
    /// give up 0.3 s after the command exited.
    private func read(_ fd: Int32, onOutput: @Sendable (Data) -> Void) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 16384)
        var batch = Data()
        var lastFlush = Date()
        func flush() {
            guard !batch.isEmpty else { return }
            onOutput(batch)
            batch = Data()
            lastFlush = Date()
        }
        while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 50)
            if ready > 0 {
                let n = Darwin.read(fd, &buffer, buffer.count)
                if n <= 0 { break }
                batch.append(contentsOf: buffer[0..<n])
            } else if ready < 0, errno != EINTR {
                break
            } else if ready == 0, lock.withLock({ Date().timeIntervalSince(exitedAt) > 0.3 }) {
                break
            }
            if Date().timeIntervalSince(lastFlush) >= 0.05 { flush() }
        }
        flush()
    }

    /// SIGTERM to the whole group; SIGKILL after 2 s if anything is left. `force` skips the wait (app quit).
    func stop(force: Bool = false) {
        killpg(pid, force ? SIGKILL : SIGTERM)
        guard !force else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            if !lock.withLock({ done }) { killpg(pid, SIGKILL) }
        }
    }
}
