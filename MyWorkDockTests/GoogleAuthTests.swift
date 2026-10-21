import XCTest
@testable import MyWorkDock

/// What the fake Google answered, and every request it saw. Shared with the calendar store tests.
final class FakeGoogle: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    /// Token endpoint reply: (status, json).
    var token: (Int, String) = (200, #"{"access_token":"at-1","expires_in":3600,"refresh_token":"rt-1"}"#)
    var primary: (Int, String) = (200, #"{"id":"me@devxlabs.ai"}"#)
    /// Held back until `release()` so two callers can pile up on one refresh.
    var delay: TimeInterval = 0

    var requests: [URLRequest] { lock.withLock { _requests } }
    func count(containing path: String) -> Int { requests.filter { $0.url?.absoluteString.contains(path) == true }.count }

    var transport: HTTPTransport {
        { [self] request in
            lock.withLock { _requests.append(request) }
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            let url = request.url!.absoluteString
            let (status, body) = url.contains("oauth2.googleapis.com/token") ? token : url.contains("/revoke") ? (200, "{}") : primary
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func body(of request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }
}

final class GoogleAuthTests: XCTestCase {
    private let config = GoogleOAuthConfig(clientID: "client-1.apps.googleusercontent.com", clientSecret: "GOCSPX-secret")
    private var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appending(path: "mwd-google-\(UUID().uuidString)/google-calendar.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func auth(_ google: FakeGoogle, now: @escaping @Sendable () -> Date = { Date() }) -> GoogleAuth {
        GoogleAuth(config: config, file: file, transport: google.transport, now: now)
    }

    private func save(_ token: GoogleToken) throws {
        XCTAssertNil(SecretFile.save(try JSONEncoder().encode(token), to: file))
    }

    private func expired(clientID: String? = nil) -> GoogleToken {
        GoogleToken(clientID: clientID ?? config.clientID, refreshToken: "rt-old", accessToken: "at-old",
                    expiresAt: Date(timeIntervalSinceNow: -10), email: "me@devxlabs.ai")
    }

    // MARK: PKCE and the sign-in URL

    func testPKCEMatchesRFC7636Vector() {
        // RFC 7636 appendix B.
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(PKCE.verifier().count, 43)
        XCTAssertNotEqual(PKCE.state(), PKCE.state())
    }

    func testAuthorizationURLCarriesEveryParameter() throws {
        let url = auth(FakeGoogle()).authorizationURL(redirect: "http://127.0.0.1:5050/", state: "st", challenge: "ch")
        let items = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(items["client_id"], config.clientID)
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:5050/")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["scope"], "https://www.googleapis.com/auth/calendar.readonly")
        XCTAssertEqual(items["code_challenge"], "ch")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], "st")
        XCTAssertEqual(items["access_type"], "offline")
        XCTAssertEqual(items["prompt"], "consent")
        XCTAssertEqual(items["hd"], "devxlabs.ai")
    }

    func testFormEncodingKeepsOnlyUnreservedCharacters() {
        XCTAssertEqual(HTTP.form([("code", "4/0A+b c"), ("n", "a-b_c.d~e")]), "code=4%2F0A%2Bb%20c&n=a-b_c.d~e")
    }

    // MARK: Sign-in

    func testSignInStoresTheTokenAndReturnsTheAccountEmail() async throws {
        let google = FakeGoogle()
        let auth = auth(google)
        let email = try await auth.signIn(code: "code-1", verifier: "ver-1", redirect: "http://127.0.0.1:1/")
        XCTAssertEqual(email, "me@devxlabs.ai")
        let sent = google.body(of: try XCTUnwrap(google.requests.first))
        XCTAssertTrue(sent.contains("grant_type=authorization_code"))
        XCTAssertTrue(sent.contains("code_verifier=ver-1"))
        XCTAssertTrue(sent.contains("client_secret=GOCSPX-secret"))
        let stored = try JSONDecoder().decode(GoogleToken.self, from: try XCTUnwrap(SecretFile.load(file)))
        XCTAssertEqual(stored.refreshToken, "rt-1")
        XCTAssertEqual(stored.clientID, config.clientID)
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "at-1")
    }

    func testNoRefreshTokenFailsSignIn() async {
        let google = FakeGoogle()
        google.token = (200, #"{"access_token":"at-1","expires_in":3600}"#)
        do {
            _ = try await auth(google).signIn(code: "c", verifier: "v", redirect: "r")
            XCTFail("expected noRefreshToken")
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, .noRefreshToken)
        }
        XCTAssertNil(SecretFile.load(file))
    }

    func testDisabledCalendarApiSurfacesGoogleMessage() async {
        let google = FakeGoogle()
        google.primary = (403, #"{"error":{"code":403,"message":"Google Calendar API has not been used in project 1 before or it is disabled."}}"#)
        do {
            _ = try await auth(google).signIn(code: "c", verifier: "v", redirect: "r")
            XCTFail("expected a server error")
        } catch {
            XCTAssertEqual(error as? GoogleAuthError, .server("Google Calendar API has not been used in project 1 before or it is disabled."))
        }
        XCTAssertNil(SecretFile.load(file)) // not signed in: nothing saved
    }

    func testTokenFileIs0600() async throws {
        _ = try await auth(FakeGoogle()).signIn(code: "c", verifier: "v", redirect: "r")
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue, 0o600)
    }

    // MARK: Refresh

    func testSavedTokenIsPickedUpAtLaunchOnlyForTheSameClient() throws {
        try save(expired())
        XCTAssertEqual(auth(FakeGoogle()).initialEmail, "me@devxlabs.ai")
        try save(expired(clientID: "another-client"))
        XCTAssertNil(auth(FakeGoogle()).initialEmail)
        XCTAssertNotNil(SecretFile.load(file)) // another client's token is ignored, not deleted
    }

    func testFreshTokenIsReusedWithoutAnyRequest() async throws {
        var token = expired()
        token.expiresAt = Date(timeIntervalSinceNow: 3000)
        try save(token)
        let google = FakeGoogle()
        let value = try await auth(google).accessToken()
        XCTAssertEqual(value, "at-old")
        XCTAssertTrue(google.requests.isEmpty)
    }

    func testRefreshSingleFlight() async throws {
        try save(expired())
        let google = FakeGoogle()
        google.delay = 0.2
        google.token = (200, #"{"access_token":"at-new","expires_in":3600}"#)
        let auth = auth(google)
        async let first = auth.accessToken()
        async let second = auth.accessToken()
        let values = try await [first, second]
        XCTAssertEqual(values, ["at-new", "at-new"])
        XCTAssertEqual(google.count(containing: "oauth2.googleapis.com/token"), 1) // two callers, one refresh
        let stored = try JSONDecoder().decode(GoogleToken.self, from: try XCTUnwrap(SecretFile.load(file)))
        XCTAssertEqual(stored.refreshToken, "rt-old") // Google did not rotate it
        XCTAssertEqual(stored.accessToken, "at-new")
    }

    func testInvalidGrantDeletesFileOthersKeepIt() async throws {
        try save(expired())
        let google = FakeGoogle()
        google.token = (400, #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#)
        let auth = auth(google)
        do { _ = try await auth.accessToken(); XCTFail("expected invalidGrant") } catch { XCTAssertEqual(error as? GoogleAuthError, .invalidGrant) }
        XCTAssertNil(SecretFile.load(file))
        do { _ = try await auth.accessToken(); XCTFail("expected notSignedIn") } catch { XCTAssertEqual(error as? GoogleAuthError, .notSignedIn) }

        try save(expired())
        google.token = (401, #"{"error":"invalid_client"}"#)
        let second = self.auth(google)
        do { _ = try await second.accessToken(); XCTFail("expected invalidClient") } catch { XCTAssertEqual(error as? GoogleAuthError, .invalidClient) }
        XCTAssertNotNil(SecretFile.load(file)) // a misconfigured build must not cost the user their session

        google.token = (503, "upstream down")
        do { _ = try await second.accessToken(); XCTFail("expected a server error") } catch { guard case .server = error as? GoogleAuthError else { return XCTFail("\(error)") } }
        XCTAssertNotNil(SecretFile.load(file))
    }

    func testInvalidateForcesOneRefreshOnlyForTheFailedToken() async throws {
        var token = expired()
        token.expiresAt = Date(timeIntervalSinceNow: 3000)
        try save(token)
        let google = FakeGoogle()
        google.token = (200, #"{"access_token":"at-new","expires_in":3600}"#)
        let auth = auth(google)
        await auth.invalidate("some-older-token")
        let untouched = try await auth.accessToken()
        XCTAssertEqual(untouched, "at-old") // a stale 401 must not throw away a newer token
        await auth.invalidate("at-old")
        let refreshed = try await auth.accessToken()
        XCTAssertEqual(refreshed, "at-new")
    }

    func testSignOutDeletesTheFileFirstAndRevokes() async throws {
        try save(expired())
        let google = FakeGoogle()
        let auth = auth(google)
        await auth.signOut()
        XCTAssertNil(SecretFile.load(file))
        XCTAssertEqual(google.count(containing: "/revoke"), 1)
        XCTAssertTrue(google.body(of: try XCTUnwrap(google.requests.last)).contains("token=rt-old"))
        do { _ = try await auth.accessToken(); XCTFail("expected notSignedIn") } catch { XCTAssertEqual(error as? GoogleAuthError, .notSignedIn) }
    }

    func testSignOutDuringARefreshDoesNotBringTheSessionBack() async throws {
        try save(expired())
        let google = FakeGoogle()
        google.delay = 0.2
        google.token = (200, #"{"access_token":"at-new","expires_in":3600}"#)
        let auth = auth(google)
        async let late = auth.accessToken()
        try await Task.sleep(for: .seconds(0.05))
        await auth.signOut()
        do { _ = try await late; XCTFail("expected the refresh to be dropped") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(SecretFile.load(file))
    }

    // MARK: Config

    func testConfigNeedsBothValuesAndIgnoresUnresolvedBuildSettings() {
        XCTAssertNil(GoogleOAuthConfig.fromBundle(Bundle(for: GoogleAuthTests.self))) // the test bundle has no client
    }
}
