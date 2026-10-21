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
    private static func grid(_ name: String, theme: ThemeMode = .dark, _ mode: CalendarMode, menuOpen: Bool = false, selecting title: String? = nil, allGuests: Bool = false,
                             scrolledTo scrollTitle: String? = nil) -> SnapshotRunner.State {
        SnapshotRunner.State(name, .panel) {
            $0.setTheme(theme)
            $0.mainTab = .calendar
            $0.calendar.preview(.signedIn(email: "aditya.thummar@devxlabs.ai"), mode: mode, menuOpen: menuOpen, selecting: title, allGuests: allGuests,
                                scrolledTo: scrollTitle)
            $0.openPanel()
        }
    }

    /// The hover peek with today's events under the ears, on the sample Wednesday (10:30, or `at` when given). They hang below the
    /// strip, so these use the panel canvas: the 120 pt notch crop would cut them off.
    private static func peek(_ name: String, theme: ThemeMode = .dark, claudex: Bool = false, at: Date? = nil) -> SnapshotRunner.State {
        SnapshotRunner.State(name, .panel) {
            $0.setTheme(theme)
            if claudex { $0.setPeekEnabled(.claudex, true) }
            $0.calendar.preview(.signedIn(email: "aditya.thummar@devxlabs.ai"))
            if let at { $0.calendar.now = { at } }
            $0.setPeekEnabled(.events, true)
            $0.pointer(inside: true)
        }
    }

    /// The panel as a click on an event in the peek leaves it: hover, then `showEvent`.
    private static func peekClick(_ name: String, theme: ThemeMode = .dark, title: String) -> SnapshotRunner.State {
        SnapshotRunner.State(name, .panel) {
            $0.setTheme(theme)
            $0.calendar.preview(.signedIn(email: "aditya.thummar@devxlabs.ai"))
            $0.setPeekEnabled(.events, true)
            $0.pointer(inside: true)
            if let row = $0.peekEvents?.rows.first(where: { $0.title == title }) { $0.showEvent(row.event) }
        }
    }

    static let all: [SnapshotRunner.State] = [
        peekClick("calendar-peek-click", title: "Hotfix triage"),
        peek("calendar-peek-events"),
        peek("calendar-peek-events-light", theme: .light),
        peek("calendar-peek-events-claudex", claudex: true),
        peek("calendar-peek-events-empty", at: CalendarSample.date(21, 20, 0)),
        // claudex on takes the other peek sources off and locks them, but not today's events.
        .fragment("calendar-settings-peek", rect: CGRect(x: 260, y: 46, width: 480, height: 380)) {
            SettingsPopover(theme: .dark, tint: .lime, peekOn: [.claudex, .events], page: .peek)
        },
        grid("calendar-week", .week),
        // What an event clicked in the peek scrolls the grid to: an hour above it (Gym starts at 18:30).
        grid("calendar-week-scrolled", .week, scrolledTo: "Gym"),
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
