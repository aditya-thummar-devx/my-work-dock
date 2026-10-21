import XCTest
@testable import MyWorkDock

/// The engine against real files in a temporary folder: what it reads, what it leaves for later, what it never counts twice.
final class UsageEngineTests: XCTestCase {
    private var dir: URL!
    private let now = UsageFixture.date("2026-10-21T18:00:00Z")
    private let utc = UsageFixture.calendar()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var projects: URL { dir.appendingPathComponent("projects") }
    private var stateURL: URL { dir.appendingPathComponent("state.json") }

    private func line(_ id: String, out: Int, at stamp: String = "2026-10-21T10:00:00Z") -> String {
        UsageFixture.line(id, at: stamp, out: out)
    }

    @discardableResult
    private func write(_ path: String, _ text: String) throws -> URL {
        let url = projects.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func total(_ engine: UsageEngine) async -> Int {
        await engine.refresh(now: now, calendar: utc).today.tokens.total
    }

    func testTheFirstLookReadsSessionsAndTheirSubagents() async throws {
        try write("-proj-a/s1.jsonl", line("m1", out: 1_000) + "\n" + line("m2", out: 2_000) + "\n")
        try write("-proj-a/s1/subagents/agent-x.jsonl", line("m3", out: 4_000) + "\n")
        try write("-proj-a/notes.txt", line("m4", out: 8_000) + "\n") // not a transcript
        let s = await UsageEngine(root: projects, stateURL: nil).refresh(now: now, calendar: utc)
        XCTAssertEqual(s.today.tokens.total, 7_000)
        XCTAssertEqual(s.month.tokens.total, 7_000)
        XCTAssertFalse(s.noData)
    }

    func testALaterLookReadsOnlyWhatWasAppended() async throws {
        // Six lines make the file longer than the 1 KB whose fingerprint tells a replaced file from a grown one.
        let first = (1...6).map { line("m\($0)", out: $0 * 1_000) }
        let file = try write("-p/s1.jsonl", first.joined(separator: "\n") + "\n")
        let engine = UsageEngine(root: projects, stateURL: nil)
        let before = await total(engine)
        XCTAssertEqual(before, 21_000)

        // Rename the last message in place (same length), then append: a read from the top would count "mX" as a new call.
        let renamed = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: #""id":"m6""#, with: #""id":"mX""#)
        try Data(renamed.utf8).write(to: file)
        try append(line("m7", out: 500) + "\n", to: file)
        let after = await total(engine)
        XCTAssertEqual(after, 21_500)
    }

    func testALineStillBeingWrittenWaitsForItsNewline() async throws {
        let file = try write("-p/s1.jsonl", line("m1", out: 100) + "\n")
        let whole = line("m2", out: 200)
        try append(String(whole.prefix(70)), to: file) // the writer is half way through the second line
        let engine = UsageEngine(root: projects, stateURL: nil)
        let half = await total(engine)
        XCTAssertEqual(half, 100)
        try append(String(whole.dropFirst(70)) + "\n", to: file)
        let done = await total(engine)
        XCTAssertEqual(done, 300)
    }

    func testTheSameMessageInTwoFilesCountsOnce() async throws {
        // A resumed or forked session copies the old lines into a new file.
        try write("-p/original.jsonl", line("m1", out: 1_000) + "\n" + line("m2", out: 2_000) + "\n")
        try write("-p/resumed.jsonl", line("m1", out: 1_000) + "\n" + line("m2", out: 2_000) + "\n" + line("m3", out: 5) + "\n")
        let counted = await total(UsageEngine(root: projects, stateURL: nil))
        XCTAssertEqual(counted, 3_005)
    }

    func testAFileReplacedByAShorterOneStartsOverWithoutCountingTwice() async throws {
        let file = try write("-p/s1.jsonl", line("m1", out: 1_000) + "\n" + line("m2", out: 2_000) + "\n")
        let engine = UsageEngine(root: projects, stateURL: nil)
        let before = await total(engine)
        XCTAssertEqual(before, 3_000)
        try Data((line("m3", out: 7) + "\n").utf8).write(to: file) // shorter than what was already read
        let after = await total(engine)
        XCTAssertEqual(after, 3_007)
    }

    func testADeletedTranscriptKeepsItsTotals() async throws {
        let file = try write("-p/s1.jsonl", line("m1", out: 1_000) + "\n")
        let engine = UsageEngine(root: projects, stateURL: nil)
        let before = await total(engine)
        XCTAssertEqual(before, 1_000)
        try FileManager.default.removeItem(at: file) // Claude Code cleans up after 30 days
        let after = await total(engine)
        XCTAssertEqual(after, 1_000)
    }

    func testTheStateSurvivesARestartAndNothingIsReadTwice() async throws {
        try write("-p/s1.jsonl", line("m1", out: 1_000) + "\n")
        let first = UsageEngine(root: projects, stateURL: stateURL)
        let before = await total(first)
        XCTAssertEqual(before, 1_000)

        let second = UsageEngine(root: projects, stateURL: stateURL)
        let remembered = await second.snapshot(now: now, calendar: utc)
        XCTAssertEqual(remembered.today.tokens.total, 1_000) // before any scan
        XCTAssertFalse(remembered.noData)
        let again = await total(second)
        XCTAssertEqual(again, 1_000)
    }

    func testAMissingFolderMeansNoDataUntilTranscriptsAppear() async throws {
        let engine = UsageEngine(root: projects, stateURL: nil)
        let empty = await engine.refresh(now: now, calendar: utc)
        XCTAssertTrue(empty.noData)
        XCTAssertEqual(empty.today.tokens.total, 0)

        try write("-p/s1.jsonl", line("m1", out: 9) + "\n")
        let found = await engine.refresh(now: now, calendar: utc)
        XCTAssertFalse(found.noData)
        XCTAssertEqual(found.today.tokens.total, 9)
    }

    func testEveryLineIsCountedAcrossReadBlocks() async throws {
        // About 8 MB: more than one 4 MB block, so lines straddle the block boundary.
        let lines = (0..<25_000).map { line("m\($0)", out: 1) }
        try write("-p/big.jsonl", lines.joined(separator: "\n") + "\n")
        let counted = await total(UsageEngine(root: projects, stateURL: nil))
        XCTAssertEqual(counted, 25_000)
    }

    func testALineLongerThanABlockIsStillRead() async throws {
        let padding = String(repeating: "x", count: 5_000_000)
        let long = #"{"type":"assistant","timestamp":"2026-10-21T10:00:00Z","message":{"id":"long","model":"claude-opus-4-8","content":[{"type":"text","text":"\#(padding)"}],"usage":{"input_tokens":0,"output_tokens":42}}}"#
        try write("-p/long.jsonl", line("m1", out: 1) + "\n" + long + "\n" + line("m2", out: 2) + "\n")
        let counted = await total(UsageEngine(root: projects, stateURL: nil))
        XCTAssertEqual(counted, 45)
    }

    // MARK: Damaged or odd situations

    func testAFolderThatCannotBeListedDoesNotMakeEveryFileLookDeleted() async throws {
        // A call this old is forgotten by the ids the ledger keeps (120 days) but its day total stays; reading the file from the top
        // again would add it a second time. That is what happens if every read position is dropped while the folder is unreachable.
        try write("-p/s1.jsonl", line("old", out: 5_000, at: "2026-04-04T10:00:00Z") + "\n")
        let engine = UsageEngine(root: projects, stateURL: stateURL)
        _ = await engine.refresh(now: now, calendar: utc)

        let away = dir.appendingPathComponent("away")
        try FileManager.default.moveItem(at: projects, to: away) // as when a volume is unmounted
        let during = await engine.refresh(now: now, calendar: utc)
        XCTAssertEqual(during.month.tokens.total, 0)
        try FileManager.default.moveItem(at: away, to: projects)
        _ = await engine.refresh(now: now, calendar: utc)

        let saved = try XCTUnwrap(JSONFile.load(UsageLedger.self, from: stateURL))
        XCTAssertEqual(saved.days["2026-04-04"]?["claude-opus-4-8"]?.output, 5_000)
        XCTAssertEqual(saved.files.count, 1)
    }

    func testAMissingFolderIsNotAScan() async throws {
        let engine = UsageEngine(root: projects, stateURL: stateURL)
        let none = await engine.refresh(now: now, calendar: utc)
        XCTAssertTrue(none.noData)
        XCTAssertNil(JSONFile.load(UsageLedger.self, from: stateURL), "nothing was seen, so nothing is saved")
        // Claude Code is used from now on: the first look that sees the folder is the one that starts the coverage.
        try write("-p/s1.jsonl", line("m1", out: 1) + "\n")
        let later = UsageFixture.date("2026-10-30T09:00:00Z")
        _ = await engine.refresh(now: later, calendar: utc)
        let saved = try XCTUnwrap(JSONFile.load(UsageLedger.self, from: stateURL))
        XCTAssertEqual(saved.coveredFrom, later.timeIntervalSince1970 - UsageLedger.transcriptLife)
    }

    func testATranscriptRewrittenToTheSameSizeOrMoreIsReadFromTheTop() async throws {
        let file = try write("-p/s1.jsonl", line("m1", out: 1_000) + "\n" + line("m2", out: 2_000) + "\n")
        let engine = UsageEngine(root: projects, stateURL: nil)
        let before = await total(engine)
        XCTAssertEqual(before, 3_000)
        // Not shorter, so the old offset is inside the new file: resuming there would skip the start and could land mid-line.
        let replacement = [line("m3", out: 10), line("m4", out: 20), line("m5", out: 30), line("m6", out: 40)].joined(separator: "\n") + "\n"
        let oldSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertGreaterThanOrEqual(replacement.utf8.count, oldSize)
        try Data(replacement.utf8).write(to: file)
        let after = await total(engine)
        XCTAssertEqual(after, 3_000 + 100) // m3 to m6 all counted; m1 and m2 stay counted
    }

    func testAnAppendedTranscriptIsNotMistakenForAReplacedOne() async throws {
        let file = try write("-p/s1.jsonl", line("m1", out: 1_000) + "\n")
        let engine = UsageEngine(root: projects, stateURL: nil)
        _ = await total(engine)
        try append(line("m2", out: 2_000) + "\n", to: file)
        // m1 is not counted again: it would show here as 4,000 if the file had been read from the top without the ids
        let after = await total(engine)
        XCTAssertEqual(after, 3_000)
    }

    func testASavedOffsetThatMakesNoSenseIsIgnoredNotATrap() async throws {
        let file = try write("-p/s1.jsonl", line("m1", out: 100) + "\n")
        let path = file.resolvingSymlinksInPath().path
        for offset in [-1, Int.min, 9_999_999] {
            let saved = #"{"files":{"\#(path)":{"offset":\#(offset),"size":-1,"mtime":0,"head":"","headLength":0}}}"#
            try Data(saved.utf8).write(to: stateURL)
            let s = await UsageEngine(root: projects, stateURL: stateURL).refresh(now: now, calendar: utc)
            XCTAssertEqual(s.today.tokens.total, 100, "offset \(offset)")
        }
    }

    func testAStateFileThatCannotBeReadIsKeptAsideNotOverwritten() async throws {
        try write("-p/s1.jsonl", line("m1", out: 7) + "\n")
        let precious = "{\"days\": 12345, \"from\": \"a newer version\"}"
        try Data(precious.utf8).write(to: stateURL)
        let s = await UsageEngine(root: projects, stateURL: stateURL).refresh(now: now, calendar: utc)
        XCTAssertEqual(s.today.tokens.total, 7) // started fresh
        let aside = stateURL.appendingPathExtension("unreadable")
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), precious)
        XCTAssertNotNil(JSONFile.load(UsageLedger.self, from: stateURL)) // and a readable file is saved again
    }

    func testAQuietRefreshLeavesTheStateFileAlone() async throws {
        try write("-p/s1.jsonl", line("m1", out: 7) + "\n")
        let engine = UsageEngine(root: projects, stateURL: stateURL)
        _ = await engine.refresh(now: now, calendar: utc)
        let stamp = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: stateURL.path)[.modificationDate] as? Date)
        try await Task.sleep(for: .milliseconds(1_100))
        _ = await engine.refresh(now: now.addingTimeInterval(60), calendar: utc) // nothing new
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: stateURL.path)[.modificationDate] as? Date, stamp)
        _ = await engine.refresh(now: now.addingTimeInterval(2 * 86_400), calendar: utc) // two days on: the last-look time is refreshed
        XCTAssertGreaterThan(try XCTUnwrap(FileManager.default.attributesOfItem(atPath: stateURL.path)[.modificationDate] as? Date), stamp)
    }
}
