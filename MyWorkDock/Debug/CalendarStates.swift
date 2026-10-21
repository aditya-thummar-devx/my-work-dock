#if DEBUG
import SwiftUI

/// Snapshot states for My Calendar (`MyWorkDock --snapshot calendar-signin --out x.png`): every state is the sample store
/// in one auth state, no Google account needed. No reference images: these are for looking at.
enum CalendarStates {
    private static func panel(_ name: String, theme: ThemeMode = .dark, _ auth: CalendarStore.Auth) -> SnapshotRunner.State {
        SnapshotRunner.State(name, .panel) {
            $0.setTheme(theme)
            $0.mainTab = .calendar
            $0.calendar.preview(auth)
            $0.openPanel()
        }
    }

    static let all: [SnapshotRunner.State] = [
        panel("calendar-signin", .signedOut(nil)),
        panel("calendar-signin-light", theme: .light, .signedOut(nil)),
        panel("calendar-signin-waiting", .signingIn),
        panel("calendar-signin-expired", .signedOut(.expired)),
        panel("calendar-signin-failed", .signedOut(.failed("Sign-in timed out. Try again."))),
        panel("calendar-signin-unconfigured", .signedOut(.notConfigured)),
        panel("calendar-signed-in", .signedIn(email: "aditya.thummar@devxlabs.ai")),
    ]
}
#endif
