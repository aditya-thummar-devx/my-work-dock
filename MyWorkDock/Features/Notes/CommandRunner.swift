import Foundation
import Observation

/// What a Commands row offers in place of Run.
enum RunAvailability: Equatable {
    case none
    case ready
    /// Looks dangerous: a lock with the reason; clicking it asks to unlock (confirm, then Touch ID or password).
    case blocked(String)
    /// Was blocked, then unlocked by its owner this session: runs like any other.
    case unlocked
    /// Another command is running.
    case busy
}

/// Runs one saved command at a time and keeps what it printed for the run sheet.
@MainActor @Observable
final class CommandRunner {
    enum State: Equatable {
        case idle, running
        case finished(Int32)
        case stopped
    }

    /// Starts `command` in `folder`; calls back on the main actor. Returns how to stop it (`force` = no grace), nil if it could not start.
    typealias Launcher = (_ command: String, _ folder: URL,
                          _ onOutput: @escaping @MainActor (Data) -> Void,
                          _ onExit: @escaping @MainActor (Int32) -> Void) -> ((_ force: Bool) -> Void)?

    private(set) var state = State.idle
    private(set) var command = ""
    private(set) var folder: URL?
    private(set) var output = OutputBuffer()
    /// The run sheet is showing (a run in progress, or one that has finished and not been closed).
    private(set) var sheetOpen = false

    @ObservationIgnored var launch: Launcher = CommandRunner.launchReal
    @ObservationIgnored private var stopHandle: ((Bool) -> Void)?
    /// A new run, or a close, makes callbacks of the previous one stale.
    @ObservationIgnored private var generation = 0

    var isRunning: Bool { state == .running }

    /// Exact texts the owner unlocked, until the app quits. Editing a command changes its text, which locks it again.
    private(set) var unlocked: Set<String> = []
    /// Set when the Mac could not check its owner; the lock's tooltip then says why it stays locked.
    var unlockUnavailable: String?

    func unlock(_ text: String) { unlocked.insert(text) }

    func availability(of text: String) -> RunAvailability {
        if let reason = CommandSafety.blockedReason(text) {
            guard unlocked.contains(text) else { return .blocked(unlockUnavailable.map { "\(reason). Can't unlock: \($0)" } ?? reason) }
            return isRunning ? .busy : .unlocked
        }
        return isRunning ? .busy : .ready
    }

    /// Re-checks the command: a blocked one never starts unless its owner unlocked that exact text, whoever calls.
    func start(command: String, in folder: URL) {
        guard !isRunning, CommandSafety.blockedReason(command) == nil || unlocked.contains(command) else { return }
        generation += 1
        let run = generation
        self.command = command
        self.folder = folder
        output = OutputBuffer()
        sheetOpen = true
        state = .running
        stopHandle = launch(command, folder, { [weak self] data in
            guard let self, run == generation else { return }
            output.append(data)
        }, { [weak self] code in
            guard let self, run == generation else { return }
            stopHandle = nil
            state = state == .stopped ? .stopped : .finished(code)
        })
        if stopHandle == nil {
            output.append("Could not start the command.")
            state = .finished(-1)
        }
    }

    /// The Stop button: SIGTERM to the command's whole group, SIGKILL after 2 s. The sheet stays until it has exited.
    func stop() {
        guard isRunning else { return }
        state = .stopped
        stopHandle?(false)
    }

    /// The Close button: stops a running command first, then closes the sheet.
    func dismiss() {
        if isRunning { stopHandle?(false) }
        generation += 1
        stopHandle = nil
        sheetOpen = false
        state = .idle
    }

    /// App quit: no waiting, nothing left behind.
    func killNow() {
        if isRunning { stopHandle?(true) }
    }

    /// Snapshot states only.
    func showSample(command: String, folder: URL, output text: String, state: State) {
        self.command = command
        self.folder = folder
        output = OutputBuffer()
        output.append(text)
        self.state = state
        sheetOpen = true
    }

    private static func launchReal(_ command: String, _ folder: URL,
                                   _ onOutput: @escaping @MainActor (Data) -> Void,
                                   _ onExit: @escaping @MainActor (Int32) -> Void) -> ((Bool) -> Void)? {
        // `DispatchQueue.main` keeps chunk order, and the exit comes after the last chunk.
        let process = StreamingProcess.launch(command, in: folder,
            onOutput: { data in DispatchQueue.main.async { MainActor.assumeIsolated { onOutput(data) } } },
            onExit: { code in DispatchQueue.main.async { MainActor.assumeIsolated { onExit(code) } } })
        return process.map { p in { force in p.stop(force: force) } }
    }
}
