import XCTest
@testable import MyWorkDock

final class EmulatorParserTests: XCTestCase {
    func testSimulatorsKeepAvailableIOSAndMapStates() throws {
        let json = """
        {"devices":{
          "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
            {"name":"iPhone 17","udid":"A","state":"Booted","isAvailable":true},
            {"name":"iPad Air 13-inch (M3)","udid":"B","state":"Shutdown","isAvailable":true},
            {"name":"iPhone Gone","udid":"C","state":"Shutdown","isAvailable":false}],
          "com.apple.CoreSimulator.SimRuntime.watchOS-11-0":[{"name":"Watch","udid":"D","state":"Shutdown","isAvailable":true}],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-6":[{"name":"iPhone SE (3rd generation)","udid":"E","state":"Booting","isAvailable":true}]}}
        """
        let list = try XCTUnwrap(EmulatorParsers.simulators(json: Data(json.utf8)))
        XCTAssertEqual(list.map(\.id), ["A", "B", "E"]) // newest runtime first, unavailable and watchOS dropped
        XCTAssertEqual(list.map(\.status), [.running, .stopped, .booting])
        XCTAssertEqual(list[0].os, "iOS 26.5")
        XCTAssertEqual(list[1].os, "iPadOS 26.5")
        XCTAssertTrue(list[1].tablet)
        XCTAssertNil(EmulatorParsers.simulators(json: Data("nope".utf8)))
    }

    func testAvdNamesAndLabels() {
        XCTAssertEqual(EmulatorParsers.avdNames("INFO | x\nPixel_9_Pro_API_35\nPixel_Tablet\n"), ["Pixel_9_Pro_API_35", "Pixel_Tablet"])
        XCTAssertEqual(EmulatorParsers.avdDisplayName("Pixel_9_Pro_API_35"), "Pixel 9 Pro")
        XCTAssertEqual(EmulatorParsers.avdOS(configIni: "image.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\n"), "Android 15 · API 35")
        XCTAssertNil(EmulatorParsers.avdOS(configIni: "hw.ramSize=2048"))
    }

    func testAdbDevicesAndWirelessDetection() {
        let text = """
        List of devices attached
        emulator-5554          device product:sdk model:Pixel_9_Pro device:emu64a transport_id:1
        192.168.1.24:5555      device product:husky model:Pixel_8 device:husky transport_id:2
        adb-ABC123-xyz._adb-tls-connect._tcp offline

        """
        let d = EmulatorParsers.adbDevices(text)
        XCTAssertEqual(d.map(\.serial), ["emulator-5554", "192.168.1.24:5555", "adb-ABC123-xyz._adb-tls-connect._tcp"])
        XCTAssertEqual(d.map(\.isWireless), [false, true, true])
        XCTAssertTrue(d[0].isEmulator)
        XCTAssertEqual(d[1].props["model"], "Pixel_8")
        XCTAssertEqual(d[2].state, "offline")
    }

    func testDevicectlJSONAfterTableText() throws {
        let text = """
        Name  Hostname
        {"result":{"devices":[
          {"identifier":"X","hardwareProperties":{"platform":"iOS","udid":"U1"},"deviceProperties":{"name":"QA iPhone","osVersionNumber":"26.5"},"connectionProperties":{"tunnelState":"connected"}},
          {"identifier":"Y","hardwareProperties":{"platform":"watchOS","udid":"U2"},"deviceProperties":{"name":"Watch"},"connectionProperties":{"tunnelState":"connected"}},
          {"identifier":"Z","hardwareProperties":{"platform":"iOS","udid":"U3"},"deviceProperties":{"name":"Old","osVersionNumber":"18.0"},"connectionProperties":{"tunnelState":"unavailable"}}]}}
        """
        let list = try XCTUnwrap(EmulatorParsers.wirelessIOS(text))
        XCTAssertEqual(list.map(\.name), ["QA iPhone", "Old"])
        XCTAssertEqual(list.map(\.status), [.connected, .unavailable])
        XCTAssertEqual(list[0].meta, "iOS 26.5")
    }

    func testReverseList() {
        XCTAssertEqual(EmulatorParsers.reverseList("emulator-5554 tcp:3000 tcp:3001\n(reverse) tcp:8081 tcp:8081\n"),
                       [Tunnel(host: "3001", device: "3000"), Tunnel(host: "8081", device: "8081")])
        XCTAssertEqual(EmulatorParsers.reverseList(""), [])
    }
}

@MainActor
final class EmulatorStoreTests: XCTestCase {
    private func store() -> EmulatorStore { EmulatorStore(sample: false) }

    func testPortFieldsKeepDigitsOnlyAndResetCopied() {
        let s = store()
        s.copyCommand()
        XCTAssertTrue(s.copied)
        s.setHost("80a81234567")
        XCTAssertEqual(s.host, "80812")
        XCTAssertFalse(s.copied)
        s.setDevice("")
        XCTAssertEqual(s.tunnelCommand, "adb reverse tcp:… tcp:80812")
    }

    /// Records what the store would run, instead of launching anything.
    private func recording(_ s: EmulatorStore) -> () -> [String] {
        var calls: [String] = []
        s.findTool = { "/bin/\($0)" }
        s.runner = { exe, args in calls.append(([exe.split(separator: "/").last.map(String.init) ?? exe] + args).joined(separator: " ")); return ProcessResult(status: 0, out: "", err: "") }
        return { calls }
    }

    func testRunTunnelGoesStraightThroughWithTheTargetSerial() async {
        let s = store()
        let calls = recording(s)
        s.setHost("5173"); s.setDevice("5173")
        s.runTunnel()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(s.confirmer.pending)
        XCTAssertEqual(calls(), ["adb -s emulator-5554 reverse tcp:5173 tcp:5173"])
        XCTAssertEqual(s.message?.text, "Ran: adb -s emulator-5554 reverse tcp:5173 tcp:5173")
    }

    func testPlayAndConnectGoStraightThrough() async {
        let s = store()
        let calls = recording(s)
        let stopped = s.devices(.ios)[1]
        s.play(stopped)
        s.wplatform = .android
        s.wirelessAction(s.wireless[1]) // disconnected -> connect
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(s.confirmer.pending)
        // Two independent tasks, so compare without order.
        XCTAssertEqual(Set(calls()), ["xcrun simctl boot \(stopped.id)", "open -a Simulator", "adb connect 192.168.1.31:5555"])
        XCTAssertEqual(s.devices(.ios)[1].status, .booting)
    }

    func testDisconnectStopColdBootAndTunnelRemovalStillAsk() {
        let s = store()
        s.wplatform = .android
        s.wirelessAction(s.wireless[0]) // connected -> disconnect
        XCTAssertEqual(s.confirmer.pending?.command, "adb disconnect 192.168.1.24:5555")
        s.confirmer.cancel()
        s.removeTunnel(s.tunnels[0])
        XCTAssertEqual(s.confirmer.pending?.command, "adb -s emulator-5554 reverse --remove tcp:8081")
        s.confirmer.cancel()
        s.removeAllTunnels()
        XCTAssertEqual(s.confirmer.pending?.command, "adb -s emulator-5554 reverse --remove-all")
    }

    func testRestartAdbServerAsksThenKillsAndStarts() async {
        let s = store()
        let calls = recording(s)
        s.restartAdbServer()
        XCTAssertEqual(s.confirmer.pending?.command, "adb kill-server && adb start-server")
        XCTAssertTrue(calls().isEmpty)
        s.confirmer.confirm()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(Array(calls().prefix(2)), ["adb kill-server", "adb start-server"])
    }

    func testDuplicateTunnelIsNotAsked() {
        let s = store() // sample already has :8081 -> :8081
        s.runTunnel()
        XCTAssertNil(s.confirmer.pending)
        XCTAssertEqual(s.message?.text, "Tunnel :8081 → :8081 already exists")
    }

    func testStopAndColdBootCommands() {
        let s = store()
        let running = s.devices(.ios)[0]
        s.stop(running)
        XCTAssertEqual(s.confirmer.pending?.command, "xcrun simctl shutdown \(running.id)")
        s.confirmer.cancel()
        s.play(running, cold: true)
        XCTAssertEqual(s.confirmer.pending?.command,
                       "xcrun simctl shutdown \(running.id) && xcrun simctl boot \(running.id) && open -a Simulator")
    }

    func testBootingFooterAndNames() {
        let s = store()
        XCTAssertNil(s.bootingName)
        s.showBootingSample()
        XCTAssertEqual(s.bootingName, "iPhone 16 Plus")
        XCTAssertEqual(s.footer(.devices).text, "4 devices · 2 active")
    }

    func testCancelRunsNothingAndConfirmRunsOnce() async {
        let s = store()
        var ran = 0
        s.confirmer.ask(ConfirmRequest(title: "t", command: "c", note: "n", confirmTitle: "ok") { ran += 1 })
        s.confirmer.cancel()
        s.confirmer.confirm()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(ran, 0)
        s.confirmer.ask(ConfirmRequest(title: "t", command: "c", note: "n", confirmTitle: "ok") { ran += 1 })
        s.confirmer.confirm()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(ran, 1)
    }

    func testMonitoringCanBeStoppedAndStartedAgain() async {
        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func bump() { lock.withLock { n += 1 } }
            var count: Int { lock.withLock { n } }
        }
        let live = EmulatorStore()
        let calls = Calls()
        live.runner = { _, _ in calls.bump(); return ProcessResult(status: 1, out: "", err: "") }
        live.findTool = { _ in nil }
        live.startMonitoring()
        try? await Task.sleep(for: .milliseconds(150))
        let first = calls.count
        XCTAssertGreaterThan(first, 0) // the loop reads right away
        live.stopMonitoring()
        live.startMonitoring() // only possible once stop has cleared the old loop
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(calls.count, first)
        live.stopMonitoring()
    }

    func testSampleStoreNeverMonitors() {
        let s = store()
        s.startMonitoring()
        s.stopMonitoring() // nothing was started: must not crash
    }
}
