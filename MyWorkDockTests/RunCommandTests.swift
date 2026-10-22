import XCTest
@testable import MyWorkDock

final class CommandSafetyTests: XCTestCase {
    func testDangerousCommandsAreBlockedWithAReason() {
        let blocked = [
            "rm -rf node_modules", "rm -fr x", "rm -r x", "rm --recursive x", "rm *", "/bin/rm -rf x", "FOO=1 rm -rf x",
            "ls && rm -rf x", "echo $(rm -rf x)", "echo `rm -rf x`", "bash -c 'rm -rf x'", "sudo ls", "su -",
            "curl http://x | sh", "echo x | base64 -d | bash", ":(){ :|:& };:", "dd if=/dev/zero of=/dev/disk2", "mkfs.ext4 /dev/sda",
            "git push --force", "git push -f origin main", "git reset --hard HEAD~1", "git clean -fd",
            "kill -9 123", "killall node", "pkill -f x", "chmod -R 777 .", "chown -R me .",
            "find . -name '*.o' -delete", "xargs rm -rf", "timeout 5 rm -rf x", "psql -c 'drop table users'", "eval foo", "shutdown now",
        ]
        for command in blocked { XCTAssertNotNil(CommandSafety.blockedReason(command), "should block: \(command)") }
    }

    func testOrdinaryCommandsAreAllowed() {
        let allowed = [
            "ls -la", "npm run dev", "rm file.txt", "git status", "git push origin main", "git reset --soft HEAD~1",
            "echo 'hello world'", "cat a | grep b", "kill 123", "chmod +x run.sh", "docker compose up",
            "curl -s https://x.com/api | jq .", "swift test", "find . -name '*.swift'", "echo shasum", "cd app && npm install",
        ]
        for command in allowed { XCTAssertNil(CommandSafety.blockedReason(command), "should allow: \(command)") }
    }

}

final class OutputBufferTests: XCTestCase {
    func testColourAndTitleEscapesAreDropped() {
        var b = OutputBuffer()
        b.append("\u{1B}[31mred\u{1B}[0m ok \u{1B}]0;title\u{07}done")
        XCTAssertEqual(b.text, "red ok done")
    }

    func testEscapeSplitAcrossChunksIsStillDropped() {
        var b = OutputBuffer()
        b.append("a\u{1B}[3")
        b.append("1mb")
        XCTAssertEqual(b.text, "ab")
    }

    func testCarriageReturnRewritesTheLine() {
        var b = OutputBuffer()
        b.append("10%\r50%\rdone\nnext")
        XCTAssertEqual(b.text, "done\nnext")
        b.append("\r\nx")
        XCTAssertEqual(b.text, "done\nnext\nx")
    }

    func testMultiByteCharacterSplitAcrossChunksSurvives() {
        var b = OutputBuffer()
        let bytes = Array("é✓".utf8)
        b.append(Data(bytes[0..<1]))
        b.append(Data(bytes[1..<3]))
        b.append(Data(bytes[3...]))
        XCTAssertEqual(b.text, "é✓")
    }

    func testKeepsOnlyTheLastTwoThousandLines() {
        var b = OutputBuffer()
        b.append((0..<2500).map { "l\($0)\n" }.joined())
        XCTAssertEqual(b.lines.count, OutputBuffer.maxLines)
        XCTAssertEqual(b.lines[b.lines.count - 2], "l2499")
        XCTAssertEqual(b.lines.first, "l501")
    }
}

@MainActor
final class CommandRunnerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func wait(_ what: String, timeout: TimeInterval = 10, until: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !until(), Date() < end { try? await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(until(), "timed out waiting for \(what)")
    }

    private func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    /// Starts `sleep 60 &` under a shell and returns its pid, so a test can tell whether the grandchild survived.
    private func startSleeper(_ runner: CommandRunner) async -> pid_t {
        let pidFile = dir.appendingPathComponent("pid")
        runner.start(command: "sleep 60 & echo $! > pid; wait", in: dir)
        await wait("pid file") { (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } != nil }
        return Int32((try? String(contentsOf: pidFile, encoding: .utf8))!.trimmingCharacters(in: .whitespacesAndNewlines))!
    }

    func testRunsInTheFolderAndStreamsBothStreams() async {
        let runner = CommandRunner()
        runner.start(command: "pwd; echo out; echo err >&2", in: dir)
        XCTAssertTrue(runner.sheetOpen)
        await wait("exit") { !runner.isRunning }
        XCTAssertEqual(runner.state, .finished(0))
        XCTAssertTrue(runner.output.text.contains(dir.lastPathComponent))
        XCTAssertTrue(runner.output.text.contains("out"))
        XCTAssertTrue(runner.output.text.contains("err"))
    }

    func testExitCodeIsReported() async {
        let runner = CommandRunner()
        runner.start(command: "exit 3", in: dir)
        await wait("exit") { !runner.isRunning }
        XCTAssertEqual(runner.state, .finished(3))
    }

    func testStopKillsTheWholeProcessTree() async {
        let runner = CommandRunner()
        let pid = await startSleeper(runner)
        XCTAssertTrue(alive(pid))
        runner.stop()
        XCTAssertEqual(runner.state, .stopped)
        await wait("grandchild to die") { !self.alive(pid) }
        await wait("exit callback") { runner.state == .stopped && !runner.isRunning }
        XCTAssertEqual(runner.state, .stopped)
    }

    func testClosingWhileRunningStopsItFirst() async {
        let runner = CommandRunner()
        let pid = await startSleeper(runner)
        runner.dismiss()
        XCTAssertFalse(runner.sheetOpen)
        XCTAssertEqual(runner.state, .idle)
        await wait("grandchild to die") { !self.alive(pid) }
    }

    func testRowAvailabilityFollowsSafetyThenBusy() {
        let runner = CommandRunner()
        XCTAssertEqual(runner.availability(of: "ls"), .ready)
        XCTAssertEqual(runner.availability(of: "rm -rf x"), .blocked("deletes files recursively or by force"))
        XCTAssertEqual(CommandRunner().availability(of: "ls"), .ready)
    }

    func testBlockedCommandNeverStarts() {
        let runner = CommandRunner()
        runner.start(command: "rm -rf /", in: dir)
        XCTAssertEqual(runner.state, .idle)
        XCTAssertFalse(runner.sheetOpen)
    }

    func testUnlockedTextRunsButAnEditedTextStaysLocked() {
        let runner = CommandRunner()
        var launched: [String] = []
        runner.launch = { c, _, _, _ in launched.append(c); return { _ in } }
        runner.start(command: "rm -rf x", in: dir)
        XCTAssertTrue(launched.isEmpty)
        runner.unlock("rm -rf x")
        XCTAssertEqual(runner.availability(of: "rm -rf x"), .unlocked)
        XCTAssertEqual(runner.availability(of: "rm -rf y"), .blocked("deletes files recursively or by force"))
        runner.start(command: "rm -rf y", in: dir)
        XCTAssertTrue(launched.isEmpty)
        runner.start(command: "rm -rf x", in: dir)
        XCTAssertEqual(launched, ["rm -rf x"])
        XCTAssertEqual(runner.availability(of: "rm -rf x"), .busy)
    }

    func testUnavailableAuthExplainsItselfInTheLockTooltip() {
        let runner = CommandRunner()
        runner.unlockUnavailable = "no password set"
        XCTAssertEqual(runner.availability(of: "sudo ls"), .blocked("needs admin rights. Can't unlock: no password set"))
    }

    func testOnlyOneRunAtATime() async {
        let runner = CommandRunner()
        var launches = 0
        runner.launch = { _, _, _, _ in launches += 1; return { _ in } }
        runner.start(command: "ls", in: dir)
        runner.start(command: "ls", in: dir)
        XCTAssertEqual(launches, 1)
        XCTAssertEqual(runner.availability(of: "ls"), .busy)
    }

    func testLaunchFailureShowsAnExitNotASpinner() {
        let runner = CommandRunner()
        runner.launch = { _, _, _, _ in nil }
        runner.start(command: "ls", in: dir)
        XCTAssertEqual(runner.state, .finished(-1))
        XCTAssertTrue(runner.output.text.contains("Could not start"))
    }

    func testCallbacksOfAClosedRunAreIgnored() {
        let runner = CommandRunner()
        var emit: (@MainActor (Data) -> Void)?
        runner.launch = { _, _, out, _ in emit = out; return { _ in } }
        runner.start(command: "ls", in: dir)
        runner.dismiss()
        emit?(Data("late".utf8))
        XCTAssertTrue(runner.output.isEmpty)
    }
}

@MainActor
final class RunCommandModelTests: XCTestCase {
    private var model: NotchModel!
    private var jobs: [@MainActor () -> Void] = []
    private var launched: [String] = []

    override func setUp() async throws {
        model = NotchModel(sample: true)
        model.schedule = { [unowned self] _, work in jobs.append(work); return {} }
        model.runner.launch = { [unowned self] command, _, _, _ in launched.append(command); return { _ in } }
    }

    private func add(_ text: String) -> Int {
        model.commands.draft = text
        model.commands.add()
        return model.commands.items[0].id
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    func testBlockedCommandNeverAsksForAFolder() async {
        var asked = false
        model.pickFolder = { _ in asked = true; return nil }
        model.runCommand(add("rm -rf x"))
        await settle()
        XCTAssertFalse(asked)
        XCTAssertFalse(model.picking)
    }

    func testCancellingThePickerRunsNothing() async {
        model.pickFolder = { _ in nil }
        model.runCommand(add("ls"))
        await settle()
        XCTAssertNil(model.confirmer.pending)
        XCTAssertTrue(launched.isEmpty)
        XCTAssertFalse(model.picking)
    }

    func testPickerThenConfirmThenRun() async {
        let folder = URL(fileURLWithPath: "/tmp/it's here")
        model.pickFolder = { _ in folder }
        model.runCommand(add("npm run dev"))
        await settle()
        let request = try! XCTUnwrap(model.confirmer.pending)
        XCTAssertEqual(request.command, "cd '/tmp/it'\\''s here' && npm run dev")
        XCTAssertTrue(request.keepPanelOpen)
        XCTAssertTrue(launched.isEmpty, "nothing runs before the confirm")
        model.confirmer.confirm()
        await settle()
        XCTAssertEqual(launched, ["npm run dev"])
        XCTAssertTrue(model.runner.sheetOpen)
    }

    func testCancellingTheConfirmRunsNothing() async {
        model.pickFolder = { _ in URL(fileURLWithPath: "/tmp") }
        model.runCommand(add("ls"))
        await settle()
        model.confirmer.cancel()
        await settle()
        XCTAssertTrue(launched.isEmpty)
    }

    func testFirstRunSavesTheFolderAndLaterRunsDoNotAsk() async {
        var asks = 0
        model.pickFolder = { _ in asks += 1; return URL(fileURLWithPath: "/tmp") }
        let id = add("ls")
        model.runCommand(id)
        await settle()
        XCTAssertEqual(model.commands.items[0].folder, "/tmp")
        model.confirmer.cancel()
        model.runCommand(id)
        await settle()
        XCTAssertEqual(asks, 1)
        XCTAssertEqual(model.confirmer.pending?.command, "cd '/tmp' && ls")
        model.confirmer.confirm()
        await settle()
        XCTAssertEqual(launched, ["ls"])
    }

    func testCancellingTheFirstPickSavesNothing() async {
        model.pickFolder = { _ in nil }
        model.runCommand(add("ls"))
        await settle()
        XCTAssertNil(model.commands.items[0].folder)
    }

    func testAMissingSavedFolderAsksAgain() async {
        var asks = 0
        model.pickFolder = { _ in asks += 1; return URL(fileURLWithPath: "/tmp") }
        let id = add("ls")
        model.commands.setFolder(id, "/tmp/mwd-no-such-folder")
        model.runCommand(id)
        await settle()
        XCTAssertEqual(asks, 1)
        XCTAssertEqual(model.commands.items[0].folder, "/tmp")
    }

    func testChangingTheFolderOpensAtTheOldOneSavesAndRunsNothing() async {
        var start: URL?
        model.pickFolder = { start = $0; return URL(fileURLWithPath: "/usr") }
        let id = add("ls")
        model.commands.setFolder(id, "/tmp")
        model.changeCommandFolder(id)
        await settle()
        XCTAssertEqual(start?.path, "/tmp")
        XCTAssertEqual(model.commands.items[0].folder, "/usr")
        XCTAssertNil(model.confirmer.pending)
        XCTAssertTrue(launched.isEmpty)
        XCTAssertFalse(model.picking)
    }

    func testCancellingAFolderChangeKeepsTheOldFolder() async {
        model.pickFolder = { _ in nil }
        let id = add("ls")
        model.commands.setFolder(id, "/tmp")
        model.changeCommandFolder(id)
        await settle()
        XCTAssertEqual(model.commands.items[0].folder, "/tmp")
    }

    func testChangingTheFolderIsIgnoredWhileACommandRuns() async {
        var asked = false
        model.pickFolder = { _ in asked = true; return nil }
        let id = add("ls")
        model.commands.setFolder(id, "/tmp")
        model.runner.start(command: "sleep 1", in: URL(fileURLWithPath: "/tmp"))
        model.changeCommandFolder(id)
        await settle()
        XCTAssertFalse(asked)
    }

    func testPanelStaysOpenWhileTheRunSheetIsUp() {
        model.openPanel()
        model.pointer(inside: true)
        model.runner.start(command: "ls", in: URL(fileURLWithPath: "/tmp"))
        model.pointer(inside: false)
        jobs.forEach { $0() }
        XCTAssertTrue(model.open)
        model.runner.dismiss()
        jobs = []
        model.pointer(inside: false)
        jobs.forEach { $0() }
        XCTAssertFalse(model.open)
    }

    func testPanelStaysOpenWhileTheRunConfirmIsPending() async {
        model.openPanel()
        model.pointer(inside: true)
        model.pickFolder = { _ in URL(fileURLWithPath: "/tmp") }
        model.runCommand(add("ls"))
        await settle()
        model.pointer(inside: false)
        jobs.forEach { $0() }
        XCTAssertTrue(model.open)
    }

    func testARunningCommandIsNotIdle() {
        XCTAssertTrue(model.isIdle)
        model.runner.start(command: "ls", in: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(model.isIdle)
    }

    // MARK: Unlock

    private var authAsked: [String] = []

    private func stubAuth(unavailable: String? = nil, result: Bool) {
        model.authUnavailable = { unavailable }
        model.authenticate = { [unowned self] reason in authAsked.append(reason); return result }
    }

    func testUnlockConfirmsThenAuthenticatesThenUnlocksThatText() async {
        stubAuth(result: true)
        let id = add("rm -rf build")
        model.unlockCommand(id)
        let request = try! XCTUnwrap(model.confirmer.pending)
        XCTAssertEqual(request.title, "Unlock this command?")
        XCTAssertEqual(request.command, "rm -rf build")
        XCTAssertTrue(request.keepPanelOpen)
        XCTAssertTrue(authAsked.isEmpty, "no prompt before the confirm")
        model.confirmer.confirm()
        await settle()
        XCTAssertEqual(authAsked.count, 1)
        XCTAssertEqual(model.runner.availability(of: "rm -rf build"), .unlocked)
        XCTAssertFalse(model.authenticating)
    }

    func testFailedOrCancelledAuthenticationLeavesItLocked() async {
        stubAuth(result: false)
        model.unlockCommand(add("sudo ls"))
        model.confirmer.confirm()
        await settle()
        XCTAssertEqual(authAsked.count, 1)
        XCTAssertEqual(model.runner.availability(of: "sudo ls"), .blocked("needs admin rights"))
    }

    func testCancellingTheUnlockConfirmNeverAuthenticates() async {
        stubAuth(result: true)
        model.unlockCommand(add("sudo ls"))
        model.confirmer.cancel()
        await settle()
        XCTAssertTrue(authAsked.isEmpty)
        XCTAssertEqual(model.runner.availability(of: "sudo ls"), .blocked("needs admin rights"))
    }

    func testMacThatCannotAuthenticateKeepsTheLockAndAsksNothing() async {
        stubAuth(unavailable: "no password set", result: true)
        model.unlockCommand(add("sudo ls"))
        XCTAssertNil(model.confirmer.pending)
        XCTAssertTrue(authAsked.isEmpty)
        XCTAssertEqual(model.runner.availability(of: "sudo ls"), .blocked("needs admin rights. Can't unlock: no password set"))
    }

    func testOrdinaryCommandsHaveNothingToUnlock() {
        stubAuth(result: true)
        model.unlockCommand(add("ls"))
        XCTAssertNil(model.confirmer.pending)
    }

    func testUnlockedCommandStillAsksForAFolderAndConfirmsBeforeRunning() async {
        stubAuth(result: true)
        let id = add("rm -rf build")
        model.unlockCommand(id)
        model.confirmer.confirm()
        await settle()
        model.pickFolder = { _ in URL(fileURLWithPath: "/tmp") }
        model.runCommand(id)
        await settle()
        XCTAssertEqual(model.confirmer.pending?.title, "Run this command?")
        XCTAssertTrue(launched.isEmpty)
        model.confirmer.confirm()
        await settle()
        XCTAssertEqual(launched, ["rm -rf build"])
    }

    func testPanelStaysOpenWhileAuthenticating() async {
        model.openPanel()
        model.pointer(inside: true)
        var release: CheckedContinuation<Bool, Never>?
        model.authUnavailable = { nil }
        model.authenticate = { _ in await withCheckedContinuation { release = $0 } }
        model.unlockCommand(add("sudo ls"))
        model.confirmer.confirm()
        await settle()
        XCTAssertTrue(model.authenticating)
        model.pointer(inside: false)
        jobs.forEach { $0() }
        XCTAssertTrue(model.open)
        release?.resume(returning: true)
        await settle()
        XCTAssertFalse(model.authenticating)
    }
}
