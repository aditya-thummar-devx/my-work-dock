import AppKit
import Foundation
import Observation

/// My Calendar. For now the Google sign-in state machine; the events arrive with the data layer.
/// signedOut → signingIn (browser open, listener waiting) → signedIn. A refresh that dies with `invalid_grant` brings back
/// signedOut(.expired). `google == nil` (snapshots, tests, a build without an OAuth client) never touches the network.
@MainActor @Observable
final class CalendarStore {
    enum SignedOutReason: Equatable {
        case expired
        case failed(String)
        case notConfigured
    }

    enum Auth: Equatable {
        case signedOut(SignedOutReason?)
        case signingIn
        case signedIn(email: String)
    }

    private(set) var auth: Auth
    let confirmer: Confirmer
    @ObservationIgnored let live: Bool
    @ObservationIgnored private let google: GoogleAuth?
    /// Opens the Google consent page. Injected by tests, which play the browser.
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Right before the browser opens (the open panel floats above it) and after a successful sign-in.
    @ObservationIgnored var willOpenBrowser: (() -> Void)?
    @ObservationIgnored var onSignedIn: (() -> Void)?
    @ObservationIgnored private var flow: Task<Void, Never>?
    /// Identifies the running sign-in: a cancelled one finishing late must not overwrite the next one's state.
    @ObservationIgnored private var flowID = 0

    static let signInTimeout: TimeInterval = 300

    init(google: GoogleAuth?, confirmer: Confirmer, live: Bool = true) {
        self.google = google
        self.confirmer = confirmer
        self.live = live
        if let google {
            auth = google.initialEmail.map { .signedIn(email: $0) } ?? .signedOut(nil)
        } else {
            auth = .signedOut(.notConfigured)
        }
    }

    static func live(confirmer: Confirmer) -> CalendarStore {
        let google = GoogleOAuthConfig.fromBundle().map { GoogleAuth(config: $0, file: JSONFile.url("google-calendar.json")) }
        return CalendarStore(google: google, confirmer: confirmer)
    }

    static func sample(_ auth: Auth = .signedOut(nil)) -> CalendarStore {
        let store = CalendarStore(google: nil, confirmer: Confirmer(), live: false)
        store.auth = auth
        return store
    }

    #if DEBUG
    /// Snapshots draw each sign-in state.
    func preview(_ auth: Auth) { self.auth = auth }
    #endif

    var isSigningIn: Bool { auth == .signingIn }

    var footer: StatusMessage {
        switch auth {
        case .signedOut(nil): StatusMessage(text: "Sign in to see your calendar")
        case .signedOut(.expired): StatusMessage(text: "Session expired · sign in again")
        case .signedOut(.failed(let why)): StatusMessage(text: why, isError: true)
        case .signedOut(.notConfigured): StatusMessage(text: "Google sign-in is not configured")
        case .signingIn: StatusMessage(text: "Waiting for Google…")
        case .signedIn(let email): StatusMessage(text: email)
        }
    }

    // MARK: Sign in / out

    func signIn() {
        guard let google, !isSigningIn else { return }
        auth = .signingIn
        flowID += 1
        let id = flowID
        flow = Task { await runSignIn(google, id: id) }
    }

    /// Cancel on the waiting screen; also what switching the menu off does.
    func cancelSignIn() {
        flowID += 1
        flow?.cancel()
        flow = nil
        if isSigningIn { auth = .signedOut(nil) }
    }

    func stop() { cancelSignIn() }

    /// Panel opened: proves the saved session still works. A refresh token that Google no longer accepts puts the sign-in
    /// screen back; any other failure (offline, Google down) leaves the session alone.
    func verifySession() async {
        guard let google, case .signedIn = auth else { return }
        do { _ = try await google.accessToken() } catch GoogleAuthError.invalidGrant { auth = .signedOut(.expired) } catch {}
    }

    func askSignOut() {
        guard case .signedIn(let email) = auth, let google else { return }
        confirmer.ask(ConfirmRequest(title: "Sign out of Google?", command: "Revoke MyWorkDock's access to \(email)",
                                     note: "Your calendar leaves this panel until you sign in again.", confirmTitle: "Sign out") { [weak self] in
            await google.signOut()
            self?.auth = .signedOut(nil)
        })
    }

    private func runSignIn(_ google: GoogleAuth, id: Int) async {
        let server = LoopbackServer(state: PKCE.state())
        defer { server.stop() }
        do {
            let port = try await server.start()
            let verifier = PKCE.verifier()
            let redirect = "http://127.0.0.1:\(port)/"
            let url = google.authorizationURL(redirect: redirect, state: server.state, challenge: PKCE.challenge(for: verifier))
            willOpenBrowser?()
            openURL(url)
            let code = try await server.callback(timeout: Self.signInTimeout)
            let email = try await google.signIn(code: code, verifier: verifier, redirect: redirect)
            guard id == flowID else { return }
            auth = .signedIn(email: email)
            flow = nil
            onSignedIn?()
        } catch is CancellationError {
            guard id == flowID else { return }
            auth = .signedOut(nil)
            flow = nil
        } catch {
            guard id == flowID else { return }
            auth = .signedOut(.failed(Self.message(for: error)))
            flow = nil
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LoopbackServer.Failure.denied: "Sign-in was cancelled."
        case LoopbackServer.Failure.timeout: "Sign-in timed out. Try again."
        case LoopbackServer.Failure.couldNotStart: "Could not start the local sign-in listener."
        case GoogleAuthError.noRefreshToken: "Google sent no refresh token. Remove MyWorkDock at myaccount.google.com/permissions, then sign in again."
        case GoogleAuthError.invalidClient: "Google rejected this build's OAuth client. The build is misconfigured."
        case GoogleAuthError.network: "Could not reach Google. Check your connection."
        case GoogleAuthError.server(let why): why
        default: error.localizedDescription
        }
    }
}
