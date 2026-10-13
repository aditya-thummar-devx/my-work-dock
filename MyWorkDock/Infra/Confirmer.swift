import Foundation
import Observation

/// Something that changes state and must be confirmed first, showing the exact command (CLAUDE.md rule).
struct ConfirmRequest {
    var title: String
    /// The exact command line(s) that will run.
    var command: String
    var note: String
    var confirmTitle: String
    var danger = false
    var run: @MainActor () async -> Void
}

/// One pending confirmation at a time; the open panel draws it as a sheet over a scrim.
@MainActor @Observable
final class Confirmer {
    private(set) var pending: ConfirmRequest?

    func ask(_ request: ConfirmRequest) { pending = request }
    func cancel() { pending = nil }

    func confirm() {
        guard let request = pending else { return }
        pending = nil
        Task { await request.run() }
    }
}
