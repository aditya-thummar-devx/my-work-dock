import XCTest
@testable import MyWorkDock

final class TranscriptIndexTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    private func write(_ project: String, _ id: String, _ lines: [String], age: TimeInterval = 60) throws -> URL {
        let p = dir.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        let f = p.appendingPathComponent("\(id).jsonl")
        try Data(lines.joined(separator: "\n").utf8).write(to: f)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: f.path)
        return f
    }

    private let user = #"{"type":"user","cwd":"/w/shop","gitBranch":"main","message":{"content":"Fix the checkout bug"}}"#
    private func assistant(_ input: Int, sidechain: Bool = false, model: String = "claude-opus-5-5") -> String {
        #"{"type":"assistant","isSidechain":\#(sidechain),"gitBranch":"feat/x","requestedModel":"\#(model)","message":{"model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"cache_read_input_tokens":4000,"cache_creation_input_tokens":10}}}"#
    }

    func testParsesCoreFields() throws {
        let f = try write("-w-shop", "abc", [#"{"type":"user","isMeta":true,"message":{"content":"meta"}}"#,
                                              #"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#,
                                              user, assistant(1000), assistant(999_999, sidechain: true), "{not json"])
        let s = try XCTUnwrap(TranscriptIndex.parse(f))
        XCTAssertEqual(s.id, "abc")
        XCTAssertEqual(s.project, "shop")
        XCTAssertEqual(s.branch, "feat/x")
        XCTAssertEqual(s.title, "Fix the checkout bug")
        XCTAssertEqual(s.contextTokens, 5010, "sidechain usage ignored")
        XCTAssertEqual(s.contextWindow, 200_000)
    }

    func testTitlePrefersCustomThenLatestAITitleAnd1MWindow() throws {
        let a = try write("-w", "t1", [user, #"{"type":"ai-title","aiTitle":"Old"}"#, #"{"type":"ai-title","aiTitle":"Checkout fix"}"#])
        XCTAssertEqual(TranscriptIndex.parse(a)?.title, "Checkout fix")
        let b = try write("-w", "t2", [#"{"type":"ai-title","aiTitle":"AI"}"#, #"{"type":"custom-title","customTitle":"Mine"}"#])
        XCTAssertEqual(TranscriptIndex.parse(b)?.title, "Mine")
        let c = try write("-w", "t3", [assistant(10, model: "claude-opus-5-5[1m]")])
        XCTAssertEqual(TranscriptIndex.parse(c)?.contextWindow, 1_000_000)
    }

    func testScanFiltersOldSortsNewestAndCaches() throws {
        try write("-w-shop", "a", [user], age: 100)
        try write("-w-shop", "b", [user], age: 50)
        try write("-w-shop", "old", [user], age: 31 * 86_400)
        let idx = TranscriptIndex(root: dir)
        XCTAssertEqual(idx.scan().map(\.id), ["b", "a"])
        XCTAssertEqual(idx.parses, 2)
        _ = idx.scan()
        XCTAssertEqual(idx.parses, 2, "unchanged files are not re-read")
        try write("-w-shop", "a", [user, user], age: 10)
        XCTAssertEqual(idx.scan().first?.id, "a")
        XCTAssertEqual(idx.parses, 3)
        XCTAssertEqual(idx.title(for: "b"), "Fix the checkout bug")
        XCTAssertNil(idx.title(for: "../etc"))
    }
}

final class SessionGroupsTests: XCTestCase {
    private func store() -> (URL, SessionGroups) {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("groups-\(UUID().uuidString).json")
        return (f, SessionGroups(file: f))
    }

    func testCreateRenameAssignPersist() throws {
        let (f, s) = store()
        let g = try s.create("Foxtale")
        XCTAssertThrowsError(try s.create("  "))
        XCTAssertThrowsError(try s.create("foxtale"), "unique, case-insensitively")
        try s.assign("sess-1", to: g.id)
        try s.rename(g.id, "Foxtale CMS")
        let back = SessionGroups(file: f)
        XCTAssertEqual(back.groups.first?.name, "Foxtale CMS")
        XCTAssertEqual(back.group(of: "sess-1"), g.id)
    }

    func testDeleteUngroupsAndAutoGroupOnlyTouchesUngrouped() throws {
        let (_, s) = store()
        let mine = try s.create("Mine")
        let shop = try s.create("shop")
        try s.assign("manual", to: mine.id)
        let moved = s.autoGroup([("manual", "shop"), ("a", "shop"), ("b", "site"), ("d", "unknown")])
        XCTAssertEqual(moved, 2)
        XCTAssertEqual(s.group(of: "manual"), mine.id)
        XCTAssertEqual(s.group(of: "a"), shop.id)
        XCTAssertNotNil(s.groups.first { $0.name == "site" })
        XCTAssertNil(s.group(of: "d"))
        try s.delete(mine.id)
        XCTAssertNil(s.group(of: "manual"))
    }
}

final class TerminalLauncherTests: XCTestCase {
    private let id = "24bd582e-3f62-428d-8eeb-7aae27829afb"

    func testResumeCommandQuotesAndRejectsOddIDs() {
        XCTAssertEqual(try TerminalLauncher.resumeCommand(cwd: "/w/it's", id: id), "cd '/w/it'\\''s' && claude --resume \(id)")
        for bad in ["", "abc; rm -rf ~", "$(id)", "../x"] { XCTAssertThrowsError(try TerminalLauncher.resumeCommand(cwd: "/w", id: bad), bad) }
    }

    func testPlansFallBackToTerminal() {
        let cmd = "cd '/w' && claude --resume x"
        let t = TerminalLauncher.plan(.terminal, cwd: "/w", id: "x", command: cmd)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].exe, "/usr/bin/osascript")
        XCTAssertTrue(t[0].args[1].contains(#"do script "cd '/w' && claude --resume x""#))
        for app in [OpenIn.iTerm2, .warp, .cmux, .ghostty, .kitty, .alacritty, .wezTerm] {
            let p = TerminalLauncher.plan(app, cwd: "/w", id: "x", command: cmd)
            XCTAssertTrue(p.last!.args[1].contains("tell application \"Terminal\""), "\(app) falls back")
        }
        XCTAssertEqual(TerminalLauncher.plan(.warp, cwd: "/w", id: "x", command: cmd)[0].args, ["warp://tab_config/mwd_resume_x"])
        XCTAssertEqual(TerminalLauncher.plan(.ghostty, cwd: "/w", id: "x", command: cmd)[0].args.last, cmd)
        let c = TerminalLauncher.plan(.cmux, cwd: "/w", id: "x", command: cmd, cmux: "/A/cmux.app/Contents/Resources/bin/cmux")[0]
        XCTAssertEqual(c.exe, "/A/cmux.app/Contents/Resources/bin/cmux")
        XCTAssertEqual(c.args, ["new-workspace", "--name", "Claude x", "--cwd", "/w", "--command", "claude --resume x", "--focus", "true"])
        XCTAssertEqual(TerminalLauncher.cmuxCLI(URL(fileURLWithPath: "/A/cmux.app")), "/A/cmux.app/Contents/Resources/bin/cmux")
    }

    func testWarpTabConfigRunsResumeInTheProjectAndCleansUp() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("warp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let old = d.appendingPathComponent("mwd_resume_aaaaaaaa.toml"), mine = d.appendingPathComponent("mine.toml")
        try Data("x".utf8).write(to: old); try Data("x".utf8).write(to: mine)
        let past = Date().addingTimeInterval(-600)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: mine.path)
        let stem = try TerminalLauncher.writeWarpTabConfig(dir: d, cwd: "/w/my \"shop\"", id: id)
        let text = try String(contentsOf: d.appendingPathComponent("\(stem).toml"), encoding: .utf8)
        XCTAssertTrue(text.contains(#"directory = "/w/my \"shop\"""#), text)
        XCTAssertTrue(text.contains("commands = [\"claude --resume \(id)\"]"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "stale MyWorkDock config removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mine.path), "user's own configs untouched")
    }

    func testDetectsInstalledApps() {
        let apps = TerminalLauncher.detect { ["dev.warp.Warp-Stable", "com.apple.Terminal"].contains($0) }
        XCTAssertEqual(apps.map(\.self), [.terminal, .warp])
        XCTAssertTrue(OpenIn.terminal.realPrompts)
        XCTAssertFalse(OpenIn.warp.realPrompts)
        // cmux, and Warp's preview build, are found too.
        XCTAssertEqual(TerminalLauncher.detect { ["com.cmuxterm.app", "dev.warp.Warp-Preview"].contains($0) }, [.terminal, .warp, .cmux])
    }
}

@MainActor
final class SessionsStoreTests: XCTestCase {
    private func tx(_ id: String, _ title: String, project: String = "shop", branch: String? = "main", ago: TimeInterval = 60) -> Transcript {
        Transcript(id: id, cwd: "/w/\(project)", project: project, branch: branch, title: title,
                   lastActivity: Date().addingTimeInterval(-ago), model: nil, contextTokens: nil, contextWindow: 200_000)
    }

    func testColumnsFiltersFocusAndMoves() {
        let s = SessionsStore(reader: nil, groups: SessionGroups(file: nil), defaults: nil)
        s.setTranscriptsForTesting([tx("a", "Fix checkout"), tx("b", "CMS schema", project: "admin", ago: 3 * 86_400),
                                    tx("c", "Docs", project: "site", branch: "release", ago: 10 * 86_400)])
        s.create("Foxtale")
        let fox = s.groups[0].id
        s.move("b", to: fox)
        XCTAssertEqual(s.columns.map(\.name), ["Foxtale", "Ungrouped"])
        XCTAssertEqual(s.columns[0].items.map(\.id), ["b"])
        XCTAssertEqual(s.columns[1].items.map(\.id), ["a", "c"])

        s.range = .week
        XCTAssertEqual(s.visible.map(\.id), ["a", "b"])
        s.search = "release"
        s.range = .month
        XCTAssertEqual(s.visible.map(\.id), ["c"])
        s.groupFilter = .group(fox)
        XCTAssertEqual(s.columns.map(\.name), ["Foxtale"])

        s.focus("c")
        XCTAssertEqual(s.search, "")
        XCTAssertEqual(s.groupFilter, .all)
        XCTAssertEqual(s.focusID, "c")

        s.move("b", to: SessionsStore.ungroupedID)
        XCTAssertEqual(s.columns[0].items.count, 0)
        s.create("foxtale")
        XCTAssertEqual(s.message?.error, true, "duplicate names are reported")
    }

    func testBoardLoadsUntilTheFirstLookFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sess-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let s = SessionsStore(reader: TranscriptReader(TranscriptIndex(root: root)), groups: SessionGroups(file: nil), defaults: nil)
        XCTAssertFalse(s.loaded)
        await s.refresh()
        XCTAssertTrue(s.loaded)
        XCTAssertFalse(s.loading)
        XCTAssertTrue(s.transcripts.isEmpty)
    }
}
