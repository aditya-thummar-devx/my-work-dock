import XCTest
@testable import MyWorkDock

/// The sign-in flow end to end: the test plays the browser against the real loopback listener, with a fake Google behind it.
@MainActor
final class CalendarStoreTests: XCTestCase {
    private let config = GoogleOAuthConfig(clientID: "client-1.apps.googleusercontent.com", clientSecret: "GOCSPX-secret")
    private var file: URL!
    private var google: FakeGoogle!

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appending(path: "mwd-calendar-\(UUID().uuidString)/google-calendar.json")
        google = FakeGoogle()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func store() -> CalendarStore {
        CalendarStore(google: GoogleAuth(config: config, file: file, transport: google.transport), confirmer: Confirmer())
    }

    /// What Google's page ends in: the browser is sent to the loopback redirect with `query` appended.
    private func browser(_ answer: @escaping @Sendable (_ state: String) -> String) -> (URL) -> Void {
        { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value ?? "" }
            let target = URL(string: "\(value("redirect_uri"))?\(answer(value("state")))")!
            Task.detached { _ = try? await URLSession(configuration: .ephemeral).data(from: target) }
        }
    }

    private func until(_ what: String, timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }

    func testSignInHappyPath() async throws {
        let store = store()
        var log: [String] = []
        store.willOpenBrowser = { log.append("close panel") }
        store.onSignedIn = { log.append("signed in") }
        let play = browser { "code=abc&state=\($0)" }
        store.openURL = { log.append("browser"); play($0) }
        XCTAssertEqual(store.auth, .signedOut(nil))
        store.signIn()
        XCTAssertEqual(store.auth, .signingIn)
        XCTAssertTrue(store.isSigningIn)
        await until("sign-in") { store.auth == .signedIn(email: "me@devxlabs.ai") }
        XCTAssertEqual(log, ["close panel", "browser", "signed in"]) // the panel gets out of the browser's way first
        XCTAssertNotNil(SecretFile.load(file))
        XCTAssertEqual(store.footer, StatusMessage(text: "me@devxlabs.ai"))
        XCTAssertTrue(google.body(of: google.requests[0]).contains("code=abc"))
    }

    func testCancellingInTheBrowserShowsAMessageAndKeepsNothing() async throws {
        let store = store()
        store.openURL = browser { "error=access_denied&state=\($0)" }
        store.signIn()
        await until("denied") { store.auth == .signedOut(.failed("Sign-in was cancelled.")) }
        XCTAssertNil(SecretFile.load(file))
        XCTAssertTrue(store.footer.isError)
    }

    func testAGoogleErrorIsShownAsIs() async throws {
        google.primary = (403, #"{"error":{"message":"Google Calendar API has not been used in project 1 before or it is disabled."}}"#)
        let store = store()
        store.openURL = browser { "code=abc&state=\($0)" }
        store.signIn()
        await until("failure") { store.auth == .signedOut(.failed("Google Calendar API has not been used in project 1 before or it is disabled.")) }
    }

    func testCancelOnTheWaitingScreenAndAnOldFlowCannotOverwriteTheNextOne() async throws {
        let store = store()
        store.openURL = { _ in } // the browser never comes back
        store.signIn()
        await until("waiting") { store.isSigningIn }
        store.cancelSignIn()
        XCTAssertEqual(store.auth, .signedOut(nil))
        let play = browser { "code=abc&state=\($0)" }
        store.openURL = play
        store.signIn() // the first flow is still unwinding; its CancellationError must not reset this one
        await until("second sign-in") { store.auth == .signedIn(email: "me@devxlabs.ai") }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.auth, .signedIn(email: "me@devxlabs.ai"))
    }

    func testBuildWithoutAnOAuthClientNeverStartsAFlow() {
        let store = CalendarStore(google: nil, confirmer: Confirmer())
        XCTAssertEqual(store.auth, .signedOut(.notConfigured))
        var opened = false
        store.openURL = { _ in opened = true }
        store.signIn()
        XCTAssertEqual(store.auth, .signedOut(.notConfigured))
        XCTAssertFalse(opened)
        XCTAssertFalse(store.isSigningIn)
    }

    func testSavedSessionStartsSignedIn() throws {
        let token = GoogleToken(clientID: config.clientID, refreshToken: "rt", accessToken: "at", expiresAt: Date(timeIntervalSinceNow: 3000), email: "me@devxlabs.ai")
        XCTAssertNil(SecretFile.save(try JSONEncoder().encode(token), to: file))
        XCTAssertEqual(store().auth, .signedIn(email: "me@devxlabs.ai"))
    }

    func testDeadRefreshTokenBringsBackTheSignInScreen() async throws {
        let dead = GoogleToken(clientID: config.clientID, refreshToken: "rt", accessToken: "at", expiresAt: Date(timeIntervalSinceNow: -10), email: "me@devxlabs.ai")
        XCTAssertNil(SecretFile.save(try JSONEncoder().encode(dead), to: file))
        google.token = (503, "down")
        let store = store()
        await store.verifySession()
        XCTAssertEqual(store.auth, .signedIn(email: "me@devxlabs.ai")) // Google having a bad day is not a sign-out
        google.token = (400, #"{"error":"invalid_grant"}"#)
        await store.verifySession()
        XCTAssertEqual(store.auth, .signedOut(.expired))
        XCTAssertNil(SecretFile.load(file))
        XCTAssertEqual(store.footer, StatusMessage(text: "Session expired · sign in again"))
    }

    func testSignOutAsksFirstThenForgetsTheAccount() async throws {
        let token = GoogleToken(clientID: config.clientID, refreshToken: "rt", accessToken: "at", expiresAt: Date(timeIntervalSinceNow: 3000), email: "me@devxlabs.ai")
        XCTAssertNil(SecretFile.save(try JSONEncoder().encode(token), to: file))
        let store = store()
        store.askSignOut()
        let ask = try XCTUnwrap(store.confirmer.pending)
        XCTAssertEqual(ask.confirmTitle, "Sign out")
        XCTAssertEqual(store.auth, .signedIn(email: "me@devxlabs.ai")) // nothing happens until it is confirmed
        store.confirmer.confirm()
        await until("sign-out") { store.auth == .signedOut(nil) }
        XCTAssertNil(SecretFile.load(file))
        XCTAssertEqual(google.count(containing: "/revoke"), 1)
    }
}
