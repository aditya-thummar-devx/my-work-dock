import CryptoKit
import Foundation

/// The Google OAuth client this build was made with (`Config/GoogleOAuth.xcconfig` → Info.plist). nil while either half is empty.
struct GoogleOAuthConfig: Equatable {
    var clientID: String
    var clientSecret: String

    static func fromBundle(_ bundle: Bundle = .main) -> GoogleOAuthConfig? {
        func value(_ key: String) -> String {
            let raw = (bundle.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespaces)
            return raw.hasPrefix("$(") ? "" : raw // an unresolved build setting is as good as empty
        }
        let id = value("GoogleClientID"), secret = value("GoogleClientSecret")
        return id.isEmpty || secret.isEmpty ? nil : GoogleOAuthConfig(clientID: id, clientSecret: secret)
    }
}

/// RFC 7636, S256.
enum PKCE {
    static func verifier() -> String { random(bytes: 32) }
    static func state() -> String { random(bytes: 16) }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func random(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "no secure random bytes")
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

enum HTTP {
    /// Ephemeral: no disk cache and no cookies, so calendar data and tokens never land on disk through URLSession.
    private static let session = URLSession(configuration: .ephemeral)

    static let live: HTTPTransport = { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `application/x-www-form-urlencoded`. Only unreserved characters stay as they are: a `+` in a code would otherwise read as a space.
    static func form(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }.joined(separator: "&")
    }

    /// The `error.message` of a Google API error body, if it has one.
    static func apiMessage(_ data: Data) -> String? {
        struct Body: Decodable { struct Failure: Decodable { var message: String? }; var error: Failure? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error?.message
    }
}

struct GoogleToken: Codable, Equatable {
    /// The OAuth client that minted it: a token from another client is ignored, never deleted.
    var clientID: String
    var refreshToken: String
    var accessToken: String
    var expiresAt: Date
    /// The account's primary calendar id, which is its email address.
    var email: String
}

enum GoogleAuthError: Error, Equatable {
    case notSignedIn
    /// The refresh token is dead for good (revoked, expired, password reset): sign in again.
    case invalidGrant
    /// Google rejected the OAuth client itself: this build is misconfigured.
    case invalidClient
    case noRefreshToken
    case server(String)
    case network(String)
}

/// Google sign-in for the Calendar scope: code exchange, refresh and revoke over the system browser + loopback flow.
/// The token lives in a 0600 file. Concurrent callers share a single refresh.
actor GoogleAuth {
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    /// Account-chooser hint only; the Internal consent screen is what actually keeps other accounts out.
    static let hostedDomain = "devxlabs.ai"
    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeURL = URL(string: "https://oauth2.googleapis.com/revoke")!
    private static let primaryCalendarURL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary?fields=id")!

    nonisolated let config: GoogleOAuthConfig
    /// The saved account at launch, so the store can start signed in without awaiting the actor.
    nonisolated let initialEmail: String?
    private let file: URL?
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    private var token: GoogleToken?
    private var refreshing: Task<GoogleToken, Error>?
    /// Bumped by sign-out: a refresh that finishes afterwards must not bring the session back.
    private var epoch = 0

    init(config: GoogleOAuthConfig, file: URL?, transport: @escaping HTTPTransport = HTTP.live, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.file = file
        self.transport = transport
        self.now = now
        let saved = file.flatMap(SecretFile.load).flatMap { try? JSONDecoder().decode(GoogleToken.self, from: $0) }
        token = saved?.clientID == config.clientID ? saved : nil
        initialEmail = token?.email
    }

    nonisolated func authorizationURL(redirect: String, state: String, challenge: String) -> URL {
        let query = HTTP.form([
            ("client_id", config.clientID), ("redirect_uri", redirect), ("response_type", "code"), ("scope", Self.scope),
            ("code_challenge", challenge), ("code_challenge_method", "S256"), ("state", state),
            ("access_type", "offline"), ("prompt", "consent"), ("hd", Self.hostedDomain),
        ])
        return URL(string: "\(Self.authURL)?\(query)")!
    }

    /// Authorization code → tokens → the account's primary calendar id: the account label, and proof that the Calendar API
    /// is switched on for the project. Returns the email.
    func signIn(code: String, verifier: String, redirect: String) async throws -> String {
        let reply = try await tokenRequest([
            ("grant_type", "authorization_code"), ("code", code), ("code_verifier", verifier), ("redirect_uri", redirect),
            ("client_id", config.clientID), ("client_secret", config.clientSecret),
        ])
        guard let refresh = reply.refresh_token, !refresh.isEmpty else { throw GoogleAuthError.noRefreshToken }
        var fresh = GoogleToken(clientID: config.clientID, refreshToken: refresh, accessToken: reply.access_token,
                                expiresAt: now().addingTimeInterval(TimeInterval(reply.expires_in)), email: "")
        fresh.email = try await primaryCalendarID(accessToken: fresh.accessToken)
        epoch += 1
        token = fresh
        persist()
        return fresh.email
    }

    /// A token good for at least a minute; refreshes first when it is not.
    func accessToken() async throws -> String {
        guard let current = token else { throw GoogleAuthError.notSignedIn }
        if current.expiresAt.timeIntervalSince(now()) > 60 { return current.accessToken }
        if let refreshing { return try await refreshing.value.accessToken }
        // Unstructured on purpose: one cancelled waiter must not cancel the refresh the others wait for.
        let task = Task { try await self.refresh(current) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value.accessToken
    }

    /// A 401 with this token: the next `accessToken()` refreshes, unless a newer token already replaced it.
    func invalidate(_ failed: String) {
        if token?.accessToken == failed { token?.expiresAt = .distantPast }
    }

    /// Forgets the account locally first, then revokes the grant at Google (best effort).
    func signOut() async {
        epoch += 1
        let old = token
        token = nil
        if let file { SecretFile.delete(file) }
        guard let old else { return }
        var request = URLRequest(url: Self.revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(HTTP.form([("token", old.refreshToken)]).utf8)
        _ = try? await transport(request)
    }

    // MARK: Requests

    private struct TokenReply: Decodable {
        var access_token: String
        var expires_in: Int
        var refresh_token: String?
    }

    private struct ErrorReply: Decodable {
        var error: String?
        var error_description: String?
    }

    private func refresh(_ old: GoogleToken) async throws -> GoogleToken {
        let started = epoch
        do {
            let reply = try await tokenRequest([
                ("grant_type", "refresh_token"), ("refresh_token", old.refreshToken),
                ("client_id", config.clientID), ("client_secret", config.clientSecret),
            ])
            guard started == epoch else { throw CancellationError() } // signed out meanwhile
            var next = old
            next.accessToken = reply.access_token
            next.expiresAt = now().addingTimeInterval(TimeInterval(reply.expires_in))
            if let rotated = reply.refresh_token, !rotated.isEmpty { next.refreshToken = rotated }
            token = next
            persist()
            return next
        } catch GoogleAuthError.invalidGrant {
            guard started == epoch else { throw CancellationError() }
            token = nil
            if let file { SecretFile.delete(file) } // the refresh token is dead for good; any other failure keeps it
            throw GoogleAuthError.invalidGrant
        }
    }

    private func tokenRequest(_ pairs: [(String, String)]) async throws -> TokenReply {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(HTTP.form(pairs).utf8)
        let (data, http) = try await send(request)
        if http.statusCode == 200, let reply = try? JSONDecoder().decode(TokenReply.self, from: data) { return reply }
        let failure = try? JSONDecoder().decode(ErrorReply.self, from: data)
        switch failure?.error {
        case "invalid_grant": throw GoogleAuthError.invalidGrant
        case "invalid_client", "unauthorized_client": throw GoogleAuthError.invalidClient
        default: throw GoogleAuthError.server(failure?.error_description ?? failure?.error ?? "Google answered HTTP \(http.statusCode).")
        }
    }

    private func primaryCalendarID(accessToken: String) async throws -> String {
        struct Primary: Decodable { var id: String }
        var request = URLRequest(url: Self.primaryCalendarURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await send(request)
        if http.statusCode == 200, let id = (try? JSONDecoder().decode(Primary.self, from: data))?.id { return id }
        throw GoogleAuthError.server(HTTP.apiMessage(data) ?? "Google Calendar answered HTTP \(http.statusCode).")
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw GoogleAuthError.network(error.localizedDescription)
        }
    }

    private func persist() {
        guard let file, let token, let data = try? JSONEncoder().encode(token) else { return }
        if let why = SecretFile.save(data, to: file) { NSLog("MyWorkDock: could not save the Google token: \(why)") }
    }
}
