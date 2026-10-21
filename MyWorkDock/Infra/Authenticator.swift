import LocalAuthentication

/// The Mac's own owner check: Touch ID where there is one, the login password otherwise.
enum Authenticator {
    /// Why this Mac cannot check its owner (no password set, ...); nil when it can.
    static func unavailableReason() -> String? {
        var error: NSError?
        guard !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return nil }
        return error?.localizedDescription ?? "this Mac cannot check its owner"
    }

    /// true only when the owner proved themselves; a cancel or a failure is false, with nothing to report.
    static func authenticate(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
