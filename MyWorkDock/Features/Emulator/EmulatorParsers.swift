import Foundation

/// A row of `adb devices -l`.
struct AdbDevice: Equatable {
    var serial: String
    var state: String
    var props: [String: String]

    var isEmulator: Bool { serial.hasPrefix("emulator-") }
    /// `192.168.1.24:5555` or an mDNS `adb-XXXX._adb-tls-connect._tcp` serial.
    var isWireless: Bool { serial.contains("._adb-tls-") || serial.wholeMatch(of: /\d+\.\d+\.\d+\.\d+:\d+/) != nil }
}

struct Tunnel: Identifiable, Equatable {
    var host: String
    var device: String
    var id: String { "\(device)<-\(host)" }
}

/// Pure parsers for what the emulator tools print. Each returns nil / empty on output it does not understand,
/// so the UI shows nothing rather than guessing.
enum EmulatorParsers {
    // MARK: iOS simulators

    /// `xcrun simctl list devices --json`: available iOS / iPadOS devices, Booted → running, Booting → booting.
    static func simulators(json: Data) -> [DeviceSample]? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let runtimes = root["devices"] as? [String: [[String: Any]]] else { return nil }
        var out: [(order: String, device: DeviceSample)] = []
        for (runtime, devices) in runtimes {
            // "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> ("iOS", "26.5")
            guard let tail = runtime.split(separator: ".").last, tail.hasPrefix("iOS-") else { continue }
            let version = tail.dropFirst(4).replacingOccurrences(of: "-", with: ".")
            for d in devices where (d["isAvailable"] as? Bool) ?? true {
                guard let name = d["name"] as? String, let udid = d["udid"] as? String else { continue }
                let tablet = name.hasPrefix("iPad")
                let state = (d["state"] as? String) ?? ""
                let status: PillKind = state == "Booted" ? .running : (state == "Booting" ? .booting : .stopped)
                out.append((version + name, DeviceSample(id: udid, name: name, os: (tablet ? "iPadOS " : "iOS ") + version,
                                                         tablet: tablet, status: status)))
            }
        }
        // Newest runtime first, then name, so the list does not reshuffle between refreshes.
        return out.sorted { $0.order.localizedStandardCompare($1.order) == .orderedDescending }.map(\.device)
    }

    // MARK: Android

    static func avdNames(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("INFO") && !$0.hasPrefix("WARNING") && !$0.contains(" ") }
    }

    /// `Pixel_9_Pro_API_35` -> `Pixel 9 Pro`.
    static func avdDisplayName(_ avd: String) -> String {
        avd.replacingOccurrences(of: #"_API_?\d+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
    }

    private static let androidVersions: [Int: String] = [
        36: "16", 35: "15", 34: "14", 33: "13", 32: "12L", 31: "12", 30: "11", 29: "10", 28: "9", 27: "8.1", 26: "8.0", 25: "7.1", 24: "7.0",
    ]

    /// OS label from an AVD's `config.ini`: `Android 15 · API 35`.
    static func avdOS(configIni: String) -> String? {
        guard let line = configIni.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("image.sysdir.1") }),
              let match = line.firstMatch(of: /android-(\d+)/), let api = Int(match.1) else { return nil }
        return "Android " + (androidVersions[api].map { "\($0) · API \(api)" } ?? "API \(api)")
    }

    /// `adb devices -l`.
    static func adbDevices(_ text: String) -> [AdbDevice] {
        text.split(whereSeparator: \.isNewline).dropFirst(text.hasPrefix("List of devices") ? 1 : 0).compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, !line.hasPrefix("*") else { return nil }
            var props: [String: String] = [:]
            for p in parts.dropFirst(2) {
                let kv = p.split(separator: ":", maxSplits: 1).map(String.init)
                if kv.count == 2 { props[kv[0]] = kv[1] }
            }
            return AdbDevice(serial: parts[0], state: parts[1], props: props)
        }
    }

    // MARK: iOS wireless

    /// `xcrun devicectl list devices --json-output -`. The JSON may follow table text, so cut it out first.
    static func wirelessIOS(_ text: String) -> [WirelessSample]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let root = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let devices = (root["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return nil }
        return devices.compactMap { d in
            let hw = d["hardwareProperties"] as? [String: Any] ?? [:]
            let props = d["deviceProperties"] as? [String: Any] ?? [:]
            let conn = d["connectionProperties"] as? [String: Any] ?? [:]
            guard (hw["platform"] as? String) == "iOS", let name = props["name"] as? String else { return nil }
            let udid = (hw["udid"] as? String) ?? (d["identifier"] as? String) ?? name
            let version = (props["osVersionNumber"] as? String).map { "iOS \($0)" } ?? "iOS"
            let tunnel = (conn["tunnelState"] as? String) ?? ""
            let status: PillKind = tunnel == "connected" ? .connected : (tunnel == "disconnected" ? .disconnected : .unavailable)
            return WirelessSample(id: udid, name: name, meta: version, addr: udid, status: status)
        }
    }

    // MARK: Tunnels

    /// `adb reverse --list`: lines like `emulator-5554 tcp:8081 tcp:8081` (device port first, then host port).
    static func reverseList(_ text: String) -> [Tunnel] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let ports = line.matches(of: /tcp:(\d+)/).map { String($0.1) }
            return ports.count >= 2 ? Tunnel(host: ports[1], device: ports[0]) : nil
        }
    }
}
