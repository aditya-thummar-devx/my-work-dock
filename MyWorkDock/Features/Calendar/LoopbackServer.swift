import Foundation
import Network

/// One-shot HTTP listener on 127.0.0.1 that catches Google's OAuth redirect (`/?code=…&state=…`).
/// Browsers pre-connect and ask for /favicon.ico, so every connection is answered on its own and only a request carrying
/// the right `state` ends the wait. Everything runs on one serial queue.
final class LoopbackServer: @unchecked Sendable {
    enum Failure: Error, Equatable {
        /// The user pressed Cancel at Google (`error=access_denied`).
        case denied(String)
        case timeout
        case couldNotStart(String)
    }

    enum Reply: Equatable {
        case code(String)
        case denied(String)
        case ignore
    }

    private final class Flag: @unchecked Sendable { var raised = false }

    let state: String
    private let queue = DispatchQueue(label: "MyWorkDock.loopback")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var outcome: Result<String, Error>?
    private var waiter: CheckedContinuation<String, Error>?

    init(state: String) { self.state = state }

    /// Starts listening on a free port of 127.0.0.1 only and returns the port.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw Failure.couldNotStart(error.localizedDescription) }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let answered = Flag() // the handler runs on `queue`, one call at a time
            listener.stateUpdateHandler = { state in
                guard !answered.raised else { return }
                switch state {
                case .ready:
                    answered.raised = true
                    if let port = listener.port?.rawValue, port != 0 {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: Failure.couldNotStart("no port"))
                    }
                case .failed(let error):
                    answered.raised = true
                    continuation.resume(throwing: Failure.couldNotStart(error.localizedDescription))
                default: break
                }
            }
            queue.async { self.listener = listener }
            listener.start(queue: queue)
        }
    }

    /// Waits for the redirect and returns the authorization code. Throws `Failure.denied`, `Failure.timeout`, or
    /// `CancellationError` when the task is cancelled or `stop()` is called.
    func callback(timeout: TimeInterval) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                queue.async {
                    if let outcome = self.outcome { return continuation.resume(with: outcome) }
                    self.waiter = continuation
                    self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(Failure.timeout)) }
                }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.connections.values.forEach { $0.cancel() }
            self.finish(.failure(CancellationError()))
        }
    }

    // MARK: Connections (queue only)

    private func finish(_ result: Result<String, Error>) {
        guard outcome == nil else { return }
        outcome = result
        waiter?.resume(with: result)
        waiter = nil
    }

    private func handle(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.connections[id] = nil }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    /// Only the request line matters (`GET /?code=… HTTP/1.1`), so read until the first line break.
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.contains(10) || error != nil || isComplete || buffer.count >= 4096 else {
                return self.receive(connection, buffer: buffer)
            }
            let line = String(decoding: buffer.prefix { $0 != 13 && $0 != 10 }, as: UTF8.self)
            self.respond(to: line, on: connection)
        }
    }

    private func respond(to requestLine: String, on connection: NWConnection) {
        let status: String
        let page: String
        var result: Result<String, Error>?
        switch Self.interpret(requestLine, state: state) {
        case .code(let code):
            status = "200 OK"
            page = Self.page("You are signed in", "You can close this tab and go back to MyWorkDock.")
            result = .success(code)
        case .denied(let reason):
            status = "200 OK"
            page = Self.page("Sign-in cancelled", "Nothing was shared. You can close this tab.")
            result = .failure(Failure.denied(reason))
        case .ignore:
            status = "404 Not Found"
            page = Self.page("Not found", "")
        }
        let body = Data(page.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        // The outcome is reported only after the page is on its way, so the caller's `stop()` cannot cut it off.
        connection.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            if let result { self?.finish(result) }
        })
    }

    static func interpret(_ requestLine: String, state: String) -> Reply {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + String(parts[1])), components.path == "/" else { return .ignore }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { return .ignore }
        if let error = value("error") { return .denied(error) }
        if let code = value("code"), !code.isEmpty { return .code(code) }
        return .ignore
    }

    private static func page(_ title: String, _ message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>MyWorkDock</title>\
        <meta name="viewport" content="width=device-width,initial-scale=1">\
        <style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;background:#111;color:#f5f5f7}\
        main{text-align:center}h1{font-size:22px;margin:0 0 8px}p{margin:0;color:#a1a1aa}</style></head>\
        <body><main><h1>\(title)</h1><p>\(message)</p></main></body></html>
        """
    }
}
