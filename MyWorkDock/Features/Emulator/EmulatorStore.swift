import Foundation
import Observation

enum EmuPlatform: String { case android, ios }
enum EmulatorTab: String { case devices, wireless, tunnel }

struct AdbTarget: Equatable {
    var serial: String
    var name: String
}

struct StatusMessage: Equatable {
    var text: String
    var isError = false
}

/// Simulators, emulators, wireless devices and adb reverse tunnels. Reads through `ProcessRunner`,
/// every write goes through the `Confirmer` first. `live == false` (snapshots, tests) never launches a process.
@MainActor @Observable
final class EmulatorStore {
    // View state
    var platform: EmuPlatform = .ios
    var wplatform: EmuPlatform = .ios
    private(set) var host = "8081"
    private(set) var device = "8081"
    private(set) var copied = false
    var pairAddress = ""
    var pairCode = ""
    var targetMenuOpen = false

    // Data
    private(set) var ios: [DeviceSample]
    private(set) var android: [DeviceSample]
    private(set) var wirelessIOS: [WirelessSample]
    private(set) var wirelessAndroid: [WirelessSample]
    private(set) var tunnels: [Tunnel]
    private(set) var targets: [AdbTarget]
    var targetSerial: String?
    private(set) var message: StatusMessage?
    private(set) var refreshing = false
    /// Devices we asked to boot that the tools do not report as running yet.
    private(set) var pendingBoot: [String: Date] = [:]

    let confirmer: Confirmer
    @ObservationIgnored let live: Bool
    @ObservationIgnored var runner: ProcessRunner.Runner = { exe, args in await ProcessRunner.run(exe, args) }
    @ObservationIgnored var findTool: @Sendable (String) async -> String? = { await PathResolver.find($0) }
    @ObservationIgnored var spawn: @Sendable (String, [String]) -> Bool = { ProcessRunner.spawn($0, $1) }
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var knownWireless: [KnownWireless]

    struct KnownWireless: Codable, Equatable { var addr: String; var name: String; var meta: String }
    nonisolated static var knownURL: URL { JSONFile.url("wireless-android.json") }
    static let bootTimeout: TimeInterval = 120

    init(confirmer: Confirmer? = nil) {
        self.confirmer = confirmer ?? Confirmer()
        live = true
        ios = []; android = []; wirelessIOS = []; wirelessAndroid = []; tunnels = []; targets = []
        knownWireless = JSONFile.load([KnownWireless].self, from: Self.knownURL) ?? []
    }

    /// The designs' sample content. `booting` is the prototype state right after pressing Play on iPhone 16 Plus.
    init(sample booting: Bool, confirmer: Confirmer? = nil) {
        self.confirmer = confirmer ?? Confirmer()
        live = false
        ios = booting ? SampleData.iosDevicesBooting : SampleData.iosDevices
        android = SampleData.androidDevices
        wirelessIOS = SampleData.wirelessIOS
        wirelessAndroid = SampleData.wirelessAndroid
        tunnels = SampleData.tunnels.map { Tunnel(host: $0.host, device: $0.device) }
        targets = [AdbTarget(serial: "emulator-5554", name: "Pixel 9 Pro")]
        targetSerial = "emulator-5554"
        knownWireless = []
    }

    /// Snapshot states only: the prototype right after pressing Play on iPhone 16 Plus.
    func showBootingSample() { ios = SampleData.iosDevicesBooting }

    // MARK: Derived

    /// Devices of `platform`, with devices we are still waiting on shown as booting.
    func devices(_ platform: EmuPlatform) -> [DeviceSample] {
        (platform == .ios ? ios : android).map { d in
            guard d.status == .stopped, pendingBoot[d.id] != nil else { return d }
            var d = d
            d.status = .booting
            return d
        }
    }

    private var everything: [DeviceSample] { devices(.ios) + devices(.android) }
    var bootingName: String? { everything.first { $0.status == .booting }?.name }

    var wireless: [WirelessSample] { wplatform == .ios ? wirelessIOS : wirelessAndroid }
    var target: AdbTarget? { targets.first { $0.serial == targetSerial } ?? targets.first }

    /// The preview shown under the port cards (no `-s`, as in the designs).
    var tunnelCommand: String { "adb reverse tcp:\(device.isEmpty ? "…" : device) tcp:\(host.isEmpty ? "…" : host)" }

    func footer(_ tab: EmulatorTab) -> StatusMessage {
        if let message { return message }
        switch tab {
        case .devices:
            let list = devices(platform)
            return StatusMessage(text: "\(list.count) devices · \(list.filter { $0.status != .stopped }.count) active")
        case .wireless:
            return StatusMessage(text: "\(wireless.count) wireless devices · \(wireless.filter { $0.status == .connected }.count) connected")
        case .tunnel:
            return StatusMessage(text: "\(tunnels.count) active · resets when the device reboots")
        }
    }

    // MARK: Port fields

    private static func clean(_ v: String) -> String { String(v.filter(\.isNumber).prefix(5)) }

    func setHost(_ v: String) { host = Self.clean(v); copied = false }
    func setDevice(_ v: String) { device = Self.clean(v); copied = false }
    func usePreset(_ port: String) { host = port; device = port; copied = false }

    func copyCommand() {
        Clipboard.copy(tunnelCommand)
        copied = true
    }

    // MARK: Monitoring

    /// Refreshes every 30 s, every 2 s while something is booting.
    func startMonitoring() {
        guard live, monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshDevices()
                let waiting = !self.pendingBoot.isEmpty || self.bootingName != nil
                try? await Task.sleep(for: .seconds(waiting ? 2 : 30))
            }
        }
    }

    /// Emulator menu switched off: no more polling. `startMonitoring()` can start it again.
    func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        pendingBoot = [:]
    }

    func refresh() { Task { await refreshAll() } }

    func refreshAll() async {
        guard live else { return }
        refreshing = true
        defer { refreshing = false }
        await refreshDevices()
        await refreshTunnels()
    }

    func refreshDevices() async {
        guard live else { return }
        async let sims = loadSimulators()
        async let droid = loadAndroid()
        async let wios = loadWirelessIOS()
        let (s, a, w) = await (sims, droid, wios)
        if let s { ios = s }
        if let a {
            android = a.devices
            targets = a.targets
            wirelessAndroid = a.wireless
            if target == nil || !targets.contains(where: { $0.serial == targetSerial }) { targetSerial = targets.first?.serial }
        } else {
            android = []; targets = []; wirelessAndroid = []
        }
        if let w { wirelessIOS = w }
        let now = Date()
        pendingBoot = pendingBoot.filter { id, since in
            now.timeIntervalSince(since) < Self.bootTimeout && (everythingRaw.first { $0.id == id }?.status ?? .stopped) == .stopped
        }
    }

    private var everythingRaw: [DeviceSample] { ios + android }

    func refreshTunnels() async {
        guard live else { return }
        guard let serial = target?.serial, let adb = await findTool("adb") else { tunnels = []; return }
        let r = await runner(adb, ["-s", serial, "reverse", "--list"])
        tunnels = r.ok ? EmulatorParsers.reverseList(r.out) : []
    }

    // MARK: Loading

    private func loadSimulators() async -> [DeviceSample]? {
        let r = await runner("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        return r.ok ? EmulatorParsers.simulators(json: Data(r.out.utf8)) : nil
    }

    private func loadWirelessIOS() async -> [WirelessSample]? {
        let r = await runner("/usr/bin/xcrun", ["devicectl", "list", "devices", "--quiet", "--json-output", "-"])
        return r.ok ? EmulatorParsers.wirelessIOS(r.out) : nil
    }

    private struct AndroidSnapshot {
        var devices: [DeviceSample]
        var targets: [AdbTarget]
        var wireless: [WirelessSample]
    }

    private func loadAndroid() async -> AndroidSnapshot? {
        guard let adb = await findTool("adb") else { return nil }
        let list = await runner(adb, ["devices", "-l"])
        guard list.ok else { return nil }
        let adbDevices = EmulatorParsers.adbDevices(list.out)

        // Which AVD each running emulator is, and whether it finished booting.
        var running: [String: (serial: String, booting: Bool)] = [:]
        for d in adbDevices where d.isEmulator {
            let name = await runner(adb, ["-s", d.serial, "emu", "avd", "name"]).firstLine
            guard !name.isEmpty else { continue }
            var booting = d.state != "device"
            if !booting { booting = await runner(adb, ["-s", d.serial, "shell", "getprop", "sys.boot_completed"]).text != "1" }
            running[name] = (d.serial, booting)
        }

        var avds: [String] = []
        if let emu = await findTool("emulator") {
            avds = EmulatorParsers.avdNames(await runner(emu, ["-list-avds"]).out)
        }
        let names = avds + running.keys.sorted().filter { !avds.contains($0) }
        let devices = names.map { name -> DeviceSample in
            let info = Self.avdInfo(name)
            let r = running[name]
            return DeviceSample(id: name, name: EmulatorParsers.avdDisplayName(name), os: info.os, tablet: info.tablet,
                                status: r.map { $0.booting ? .booting : .running } ?? .stopped, serial: r?.serial)
        }

        let ready = adbDevices.filter { $0.state == "device" }
        let targets = ready.map { d in
            AdbTarget(serial: d.serial, name: d.isEmulator
                      ? running.first { $0.value.serial == d.serial }.map { EmulatorParsers.avdDisplayName($0.key) } ?? d.serial
                      : Self.modelName(d))
        }

        var wireless: [WirelessSample] = []
        for d in adbDevices where d.isWireless {
            let ok = d.state == "device"
            var meta = "Android"
            if ok, let v = Optional(await runner(adb, ["-s", d.serial, "shell", "getprop", "ro.build.version.release"]).text), !v.isEmpty {
                meta = "Android \(v)"
            }
            let known = KnownWireless(addr: d.serial, name: Self.modelName(d), meta: meta)
            if ok { remember(known) }
            wireless.append(WirelessSample(id: d.serial, name: known.name, meta: known.meta, addr: d.serial, status: ok ? .connected : .unavailable))
        }
        for k in knownWireless where !wireless.contains(where: { $0.addr == k.addr }) {
            wireless.append(WirelessSample(id: k.addr, name: k.name, meta: k.meta, addr: k.addr, status: .disconnected))
        }
        return AndroidSnapshot(devices: devices, targets: targets, wireless: wireless)
    }

    private static func modelName(_ d: AdbDevice) -> String {
        (d.props["model"] ?? d.serial).replacingOccurrences(of: "_", with: " ")
    }

    private func remember(_ k: KnownWireless) {
        guard !knownWireless.contains(k) else { return }
        knownWireless.removeAll { $0.addr == k.addr }
        knownWireless.append(k)
        JSONFile.save(knownWireless, to: Self.knownURL)
    }

    /// OS label and form factor from the AVD's `config.ini`.
    private static func avdInfo(_ name: String) -> (os: String, tablet: Bool) {
        let home = ProcessInfo.processInfo.environment["ANDROID_AVD_HOME"] ?? NSHomeDirectory() + "/.android/avd"
        let ini = (try? String(contentsOfFile: "\(home)/\(name).avd/config.ini", encoding: .utf8)) ?? ""
        let tablet = name.lowercased().contains("tablet") || ini.lowercased().contains("hw.device.name=pixel_tablet")
        return (EmulatorParsers.avdOS(configIni: ini) ?? "Android", tablet)
    }

    // MARK: Messages

    func say(_ text: String, error: Bool = false) {
        message = StatusMessage(text: text, isError: error)
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    // MARK: Commands (all behind the confirm sheet)

    private static func display(_ tool: String, _ args: [String]) -> String {
        ([tool] + args.map { $0.contains(" ") ? "'\($0)'" : $0 }).joined(separator: " ")
    }

    private func shell(_ tool: String, _ args: [String]) async -> ProcessResult {
        let fixed = ["xcrun": "/usr/bin/xcrun", "open": "/usr/bin/open"]
        var path = fixed[tool]
        if path == nil { path = await findTool(tool) }
        guard let exe = path else { return .failed("\(tool) not found. Install it or add it to PATH.") }
        return await runner(exe, args)
    }

    /// Runs `work`, reports "Ran: …" or the first line of the error in the footer, then re-reads everything.
    private func execute(_ command: String, _ work: @MainActor () async -> ProcessResult) async {
        let r = await work()
        if r.ok { say("Ran: \(command)") } else { say(r.firstLine.isEmpty ? "Failed: \(command)" : r.firstLine, error: true) }
        await refreshAll()
    }

    /// Non-destructive starts (Play, Connect, Run tunnel) go straight through, as in the prototype.
    private func perform(_ command: String, _ work: @escaping @MainActor () async -> ProcessResult) {
        Task { [weak self] in await self?.execute(command, work) }
    }

    /// Stopping, restarting and removing things still asks first, showing the exact command.
    private func ask(_ title: String, _ command: String, note: String, ok: String,
                     _ work: @escaping @MainActor () async -> ProcessResult) {
        confirmer.ask(ConfirmRequest(title: title, command: command, note: note, confirmTitle: ok) { [weak self] in
            await self?.execute(command, work)
        })
    }

    private func isIOS(_ d: DeviceSample) -> Bool { ios.contains { $0.id == d.id } }

    func play(_ d: DeviceSample, cold: Bool = false) {
        let running = d.status == .running
        // Cold boot restarts a running device, so it asks; a plain Play starts one that is stopped.
        func start(_ title: String, _ command: String, note: String, ok: String, _ work: @escaping @MainActor () async -> ProcessResult) {
            if cold { ask(title, command, note: note, ok: ok, work) } else { perform(command, work) }
        }
        if isIOS(d) {
            let steps = (cold && running ? [["simctl", "shutdown", d.id]] : []) + [["simctl", "boot", d.id]]
            let command = (steps.map { Self.display("xcrun", $0) } + ["open -a Simulator"]).joined(separator: " && ")
            start("Cold boot \(d.name)?", command, note: "Restarts the simulator from scratch.", ok: "Cold boot") { [self] in
                var r = ProcessResult(status: 0, out: "", err: "")
                for step in steps { r = await shell("xcrun", step); if !r.ok && !r.err.contains("current state: Booted") { return r } }
                _ = await shell("open", ["-a", "Simulator"])
                pendingBoot[d.id] = Date()
                return ProcessResult(status: 0, out: "", err: "")
            }
        } else {
            let args = ["-avd", d.id] + (cold ? ["-no-snapshot-load"] : [])
            let kill = cold && running ? d.serial : nil
            let command = (kill.map { [Self.display("adb", ["-s", $0, "emu", "kill"])] } ?? []).joined() + (kill == nil ? "" : " && ") + Self.display("emulator", args)
            start("Cold boot \(d.name)?", command, note: "Restarts the emulator without its saved snapshot.", ok: "Cold boot") { [self] in
                if let serial = kill {
                    _ = await shell("adb", ["-s", serial, "emu", "kill"])
                    try? await Task.sleep(for: .seconds(3))
                }
                guard let emu = await findTool("emulator") else { return .failed("emulator not found. Install the Android SDK emulator.") }
                guard spawn(emu, args) else { return .failed("Could not start \(emu)") }
                pendingBoot[d.id] = Date()
                return ProcessResult(status: 0, out: "", err: "")
            }
        }
    }

    func stop(_ d: DeviceSample) {
        if isIOS(d) {
            let args = ["simctl", "shutdown", d.id]
            ask("Stop \(d.name)?", Self.display("xcrun", args), note: "Shuts the simulator down.", ok: "Stop") { [self] in
                pendingBoot[d.id] = nil
                return await shell("xcrun", args)
            }
        } else if let serial = d.serial {
            let args = ["-s", serial, "emu", "kill"]
            ask("Stop \(d.name)?", Self.display("adb", args), note: "Shuts the emulator down.", ok: "Stop") { [self] in
                pendingBoot[d.id] = nil
                return await shell("adb", args)
            }
        }
    }

    func wirelessAction(_ d: WirelessSample) {
        if wplatform == .ios { refresh(); return } // devicectl has no connect / disconnect; re-read the list
        let args = [d.status == .connected ? "disconnect" : "connect", d.addr]
        if d.status == .connected {
            ask("Disconnect \(d.name)?", Self.display("adb", args), note: "Drops the wireless connection.", ok: "Disconnect") { [self] in
                await shell("adb", args)
            }
        } else {
            perform(Self.display("adb", args)) { [self] in await shell("adb", args) }
        }
    }

    var canPair: Bool { !pairAddress.trimmingCharacters(in: .whitespaces).isEmpty && pairCode.count == 6 }

    func pair() {
        guard canPair else { say("Enter the IP:port and the 6-digit code", error: true); return }
        let addr = pairAddress.trimmingCharacters(in: .whitespaces)
        let args = ["pair", addr, pairCode]
        ask("Pair with \(addr)?", Self.display("adb", args), note: "Pairs this Mac with the device.", ok: "Pair") { [self] in
            let r = await shell("adb", args)
            if r.ok { pairAddress = ""; pairCode = "" }
            return r
        }
    }

    func runTunnel() {
        guard !host.isEmpty, !device.isEmpty else { say("Enter both ports", error: true); return }
        guard let serial = target?.serial else { say("No Android device connected", error: true); return }
        guard !tunnels.contains(Tunnel(host: host, device: device)) else { say("Tunnel :\(host) → :\(device) already exists"); return }
        let args = ["-s", serial, "reverse", "tcp:\(device)", "tcp:\(host)"]
        perform(Self.display("adb", args)) { [self] in await shell("adb", args) }
    }

    func removeTunnel(_ t: Tunnel) {
        guard let serial = target?.serial else { return }
        let args = ["-s", serial, "reverse", "--remove", "tcp:\(t.device)"]
        ask("Remove tunnel :\(t.host) → :\(t.device)?", Self.display("adb", args), note: "The device can no longer reach this port.", ok: "Remove") { [self] in
            await shell("adb", args)
        }
    }

    func removeAllTunnels() {
        guard let serial = target?.serial else { return }
        let args = ["-s", serial, "reverse", "--remove-all"]
        ask("Remove all tunnels?", Self.display("adb", args), note: "Every adb reverse tunnel on this device is dropped.", ok: "Remove all") { [self] in
            await shell("adb", args)
        }
    }

    func selectTarget(_ serial: String) {
        targetSerial = serial
        targetMenuOpen = false
        Task { await refreshTunnels() }
    }
}
