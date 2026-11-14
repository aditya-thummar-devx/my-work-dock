import Foundation
import Network

/// Browses the local network for an `_adb-tls-pairing._tcp` service matching
/// the given `AdbQRPayload`, resolves its IP and port, and reports the result.
///
/// Typical usage:
/// ```swift
/// let monitor = AdbPairingMonitor()
/// monitor.onDiscovered = { host, port in … }
/// monitor.onTimeout    = { … }
/// monitor.onFailed     = { reason in … }
/// monitor.start(payload: payload)
/// ```
@MainActor
final class AdbPairingMonitor {

    // MARK: - Callbacks

    /// Called once when the matching service is resolved to `(host, port)`.
    var onDiscovered: ((String, UInt16) -> Void)?
    /// Called when the 120-second timeout expires before discovery.
    var onTimeout: (() -> Void)?
    /// Called on a non-recoverable browse or resolution error.
    var onFailed: ((String) -> Void)?

    // MARK: - Private state

    private var browser: NWBrowser?
    private var resolveConnection: NWConnection?
    private var timeoutTask: Task<Void, Never>?
    private var fired = false

    // MARK: - Public API

    /// Start browsing for the ADB pairing service described by `payload`.
    /// Safe to call only once per monitor instance; call `stop()` before reusing.
    func start(payload: AdbQRPayload) {
        fired = false

        // 120-second timeout — matches EmulatorStore.bootTimeout
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(120))
            } catch {
                return // cancelled
            }
            await MainActor.run { [weak self] in
                guard let self, !self.fired else { return }
                self.stop()
                self.onTimeout?()
            }
        }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browserDescriptor = NWBrowser.Descriptor.bonjour(
            type: "_adb-tls-pairing._tcp",
            domain: "local."
        )

        let browser = NWBrowser(for: browserDescriptor, using: parameters)
        self.browser = browser

        let targetName = payload.serviceName

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint,
                      name == targetName else { continue }
                // Found matching service — resolve it
                Task { @MainActor [weak self] in
                    self?.resolve(endpoint: result.endpoint)
                }
                break
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed(let error) = state {
                Task { @MainActor [weak self] in
                    guard let self, !self.fired else { return }
                    self.stop()
                    self.onFailed?("Browser failed: \(error.localizedDescription)")
                }
            }
        }

        let queue = DispatchQueue(label: "com.myworkdock.adbpairing", qos: .utility)
        browser.start(queue: queue)
    }

    /// Stop browsing, cancel any in-flight resolution, and cancel the timeout.
    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil

        browser?.cancel()
        browser = nil

        resolveConnection?.cancel()
        resolveConnection = nil
    }

    // MARK: - Resolution

    /// Opens a temporary TCP connection to `endpoint`, waits for `.ready`,
    /// then reads the remote host/port from the connection path.
    private func resolve(endpoint: NWEndpoint) {
        guard !fired else { return }

        let connection = NWConnection(to: endpoint, using: .tcp)
        resolveConnection = connection

        let queue = DispatchQueue(label: "com.myworkdock.adbpairing.resolve", qos: .utility)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let path = connection.currentPath,
                      case .hostPort(let host, let port) = path.remoteEndpoint else {
                    connection.cancel()
                    Task { @MainActor [weak self] in
                        guard let self, !self.fired else { return }
                        self.stop()
                        self.onFailed?("Could not read remote endpoint after connection became ready.")
                    }
                    return
                }

                // Strip IPv6 interface suffix (e.g. "fe80::1%en0" → "fe80::1")
                let rawHost = host.debugDescription
                    .components(separatedBy: "%")
                    .first ?? host.debugDescription
                let rawPort = port.rawValue

                connection.cancel()

                Task { @MainActor [weak self] in
                    guard let self, !self.fired else { return }
                    self.fired = true
                    self.stop()
                    self.onDiscovered?(rawHost, rawPort)
                }

            case .failed(let error):
                connection.cancel()
                Task { @MainActor [weak self] in
                    guard let self, !self.fired else { return }
                    self.stop()
                    self.onFailed?("Resolution connection failed: \(error.localizedDescription)")
                }

            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}
