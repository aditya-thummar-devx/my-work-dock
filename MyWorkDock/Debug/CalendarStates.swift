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

    /// The signed-in views on the sample week (Wed 21 Oct 2026, 10:30); no network.
    private static func grid(_ name: String, theme: ThemeMode = .dark, _ mode: CalendarMode, menuOpen: Bool = false, selecting title: String? = nil, allGuests: Bool = false) -> SnapshotRunner.State {
        SnapshotRunner.State(name, .panel) {
            $0.setTheme(theme)
            $0.mainTab = .calendar
            $0.calendar.preview(.signedIn(email: "aditya.thummar@devxlabs.ai"), mode: mode, menuOpen: menuOpen, selecting: title, allGuests: allGuests)
            $0.openPanel()
        }
    }

    static let all: [SnapshotRunner.State] = [
        grid("calendar-week", .week),
        grid("calendar-week-light", theme: .light, .week),
        grid("calendar-month", .month),
        grid("calendar-month-light", theme: .light, .month),
        grid("calendar-day", .day),
        grid("calendar-calendars-menu", .week, menuOpen: true),
        grid("calendar-detail", .week, selecting: "Client call: Asaya rollout"),
        grid("calendar-detail-light", theme: .light, .week, selecting: "Client call: Asaya rollout"),
        grid("calendar-detail-simple", .month, selecting: "Dentist"),
        grid("calendar-detail-guests", .week, selecting: "Lunch"),
        grid("calendar-detail-guests-all", .week, selecting: "Lunch", allGuests: true),
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
