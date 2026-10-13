import Foundation
import Network
import Observation

/// Where the chip's address comes from (DESIGN_SPEC §3): `en0` IPv4 first, else the first private IPv4 (10/8, 172.16/12, 192.168/16).
enum LocalIP {
    static func isPrivate(_ ip: String) -> Bool {
        let o = ip.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return false }
        return o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168)
    }

    /// `interfaces` in `getifaddrs` order: running, non-loopback IPv4 addresses.
    static func pick(from interfaces: [(name: String, ip: String)]) -> String? {
        interfaces.first { $0.name == "en0" }?.ip ?? interfaces.first { isPrivate($0.ip) }?.ip
    }

    static func current() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var found: [(name: String, ip: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = entry.pointee
            let flags = Int32(bitPattern: i.ifa_flags)
            guard let addr = i.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING), flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            found.append((String(cString: i.ifa_name), String(cString: host)))
        }
        return pick(from: found)
    }
}

/// Header chip state (Prototype `ip`, `ipState`): the address, and the click sequence
/// idle → busy (spinner, 550 ms, re-read) → copied (✓, 1.5 s, address on the clipboard) → idle.
@MainActor @Observable
final class LocalIPStore {
    enum Phase { case idle, busy, copied }

    /// nil = no usable network (the chip reads `No network` and is disabled).
    private(set) var ip: String?
    private(set) var phase = Phase.idle

    @ObservationIgnored var read: () -> String?
    @ObservationIgnored var copyToClipboard: (String) -> Void = Clipboard.copy
    /// Waits `seconds`; tests replace it so a click finishes at once.
    @ObservationIgnored var pause: (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?

    static let spinnerTime: TimeInterval = 0.55
    static let copiedTime: TimeInterval = 1.5

    init(read: @escaping () -> String? = LocalIP.current) {
        self.read = read
        ip = read()
    }

    /// The running app: also re-reads whenever the network path changes.
    static func live() -> LocalIPStore {
        let store = LocalIPStore()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak store] _ in
            Task { @MainActor in store?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "MyWorkDock.localip"))
        store.monitor = monitor
        return store
    }

    /// Fixed address, nothing read: what the snapshots draw.
    static func sample(_ ip: String = "192.168.1.24") -> LocalIPStore { LocalIPStore(read: { ip }) }

    /// Panel open / network change: silently re-read.
    func refresh() {
        guard phase != .busy else { return }
        ip = read()
    }

    /// Chip click. Returns the running sequence so tests can wait for it.
    @discardableResult
    func click() -> Task<Void, Never>? {
        guard phase != .busy, ip != nil else { return nil }
        phase = .busy
        task?.cancel()
        let run = Task { [weak self] in
            await self?.pause(Self.spinnerTime)
            guard let self, !Task.isCancelled else { return }
            ip = read()
            guard let ip else { phase = .idle; return }
            copyToClipboard(ip)
            phase = .copied
            await pause(Self.copiedTime)
            if !Task.isCancelled, phase == .copied { phase = .idle }
        }
        task = run
        return run
    }

    /// Snapshot states only.
    func show(_ phase: Phase, ip: String) {
        self.phase = phase
        self.ip = ip
    }
}
