import XCTest
@testable import MyWorkDock

final class ClaudeHookInstallerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("inst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let hook = dir.appendingPathComponent("build/mwd-hook")
        try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func inst() -> ClaudeHookInstaller {
        ClaudeHookInstaller(configURL: dir.appendingPathComponent(".claude/settings.json"),
                            bundledHook: dir.appendingPathComponent("build/mwd-hook"),
                            binDir: dir.appendingPathComponent("data/bin"), backupDir: dir.appendingPathComponent("backups"))
    }

    private func read(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func handlers(_ cfg: [String: Any], _ event: String) -> [[String: Any]] {
        ((cfg["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    func testFreshInstallWritesEveryHookAndPointsAtTheDeployedCopy() throws {
        let i = inst()
        XCTAssertFalse(i.status().installed)
        XCTAssertNil(try i.install(), "nothing to back up")
        let cfg = try read(i.configURL)
        let perm = handlers(cfg, "PermissionRequest").first!
        XCTAssertTrue((perm["command"] as! String).hasPrefix("\"\(i.deployedHook.path)\""))
        XCTAssertTrue((perm["command"] as! String).hasSuffix("--event PermissionRequest --wait --timeout-secs 600"))
        XCTAssertEqual(perm["timeout"] as? Int, 610)
        for event in ["Stop", "SessionStart"] {
            let wake = handlers(cfg, event).first { ($0["command"] as! String).contains("--event Wake") }
            XCTAssertEqual(wake?["asyncRewake"] as? Bool, true, event)
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: i.deployedHook.path))
        let st = i.status()
        XCTAssertTrue(st.installed && !st.stale)
    }

    func testKeepsTheUsersHooksAndUninstallRestoresThem() throws {
        let i = inst()
        try FileManager.default.createDirectory(at: i.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-linter"]]]]]]
        try JSONSerialization.data(withJSONObject: original).write(to: i.configURL)
        let backup = try XCTUnwrap(try i.install())
        XCTAssertEqual(try read(backup) as NSDictionary, original as NSDictionary)
        XCTAssertEqual(handlers(try read(i.configURL), "PreToolUse").first?["command"] as? String, "my-linter")
        try i.uninstall()
        XCTAssertEqual(try read(i.configURL) as NSDictionary, original as NSDictionary)
    }

    func testIdempotentAndRefusesMalformedConfig() throws {
        let i = inst()
        try i.install()
        let once = try Data(contentsOf: i.configURL)
        try i.install()
        XCTAssertEqual(try Data(contentsOf: i.configURL), once)
        try Data("{oops".utf8).write(to: i.configURL)
        XCTAssertThrowsError(try i.install())
        XCTAssertEqual(String(decoding: try Data(contentsOf: i.configURL), as: UTF8.self), "{oops")
        XCTAssertNotNil(i.status().error)
    }

    func testOlderOrBrokenInstallsAreFlaggedForRepair() throws {
        let i = inst()
        try i.install()
        let text = String(decoding: try Data(contentsOf: i.configURL), as: UTF8.self)
            .replacingOccurrences(of: "--event Wake --wait --timeout-secs 86400", with: "--event Wake")
        try Data(text.utf8).write(to: i.configURL)
        XCTAssertTrue(i.status().stale)
        try i.install()
        XCTAssertFalse(i.status().stale)
        try FileManager.default.removeItem(at: i.deployedHook)
        XCTAssertTrue(i.status().stale, "hook binary missing")
    }

    func testLeavesOtherToolsHooksAlone() throws {
        let i = inst()
        try FileManager.default.createDirectory(at: i.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let peekaboo: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "\"/x/peekaboo-hook\" --agent claude --event Stop"]]]]]]
        try JSONSerialization.data(withJSONObject: peekaboo).write(to: i.configURL)
        try i.install()
        try i.uninstall()
        XCTAssertEqual(try read(i.configURL) as NSDictionary, peekaboo as NSDictionary)
    }
}
