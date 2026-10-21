import SwiftUI

extension Geo {
    enum Cal {
        static let gap: CGFloat = 10
        static let messageWidth: CGFloat = 340
        static let noteFont: CGFloat = 11.5
        static let googleHeight: CGFloat = 40
        static let googleIcon: CGFloat = 18
        static let googlePad = (leading: CGFloat(12), trailing: CGFloat(14))
        static let googleGap: CGFloat = 10
        static let menuWidth: CGFloat = 250
        /// Calendars beyond this many scroll inside the menu.
        static let menuRows = 8
    }
}

/// My Calendar: fills the open panel between the top row and the footer.
struct CalendarScreen: View {
    var store: CalendarStore

    var body: some View {
        switch store.auth {
        case .signedIn: CalendarMain(store: store).task { await store.opened() }
        default: CalendarSignIn(store: store)
        }
    }
}

/// Signed out, waiting for the browser, expired, failed, or a build without an OAuth client.
private struct CalendarSignIn: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t

    private static let intro = "Sign in with your devxlabs.ai Google account to see your events here."
    private static let accounts = "Only @devxlabs.ai accounts can sign in."

    private var copy: (title: String, message: String, problem: String?, note: String?) {
        switch store.auth {
        case .signedOut(.expired): ("Session expired", "Google signed you out. Sign in again to see your events.", nil, Self.accounts)
        case .signedOut(.failed(let why)): ("My Calendar", Self.intro, why, Self.accounts)
        case .signedOut(.notConfigured):
            ("Sign-in is not set up", "This build has no Google OAuth client. Add one in Config/GoogleOAuth.xcconfig (see the README), then rebuild.", nil, nil)
        case .signingIn: ("Waiting for Google…", "Finish signing in in your browser. This panel comes back when you are done.", nil, nil)
        default: ("My Calendar", Self.intro, nil, Self.accounts)
        }
    }

    var body: some View {
        let copy = copy
        VStack(spacing: Geo.Cal.gap) {
            if store.isSigningIn {
                Spinner(size: 24).foregroundStyle(t.muted)
            } else {
                Icon(.calendar, size: 26).foregroundStyle(t.muted)
            }
            Text(copy.title).font(Typo.display(18)).tracking(-0.4)
            Text(copy.message)
                .font(Typo.ui(13))
                .foregroundStyle(t.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Geo.Cal.messageWidth)
            if let problem = copy.problem {
                Text(problem)
                    .font(Typo.ui(12.5, .semibold))
                    .foregroundStyle(t.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Geo.Cal.messageWidth)
            }
            control.padding(.top, 4)
            if let note = copy.note {
                Text(note).font(Typo.ui(Geo.Cal.noteFont)).foregroundStyle(t.faint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var control: some View {
        switch store.auth {
        case .signedOut(.notConfigured): EmptyView()
        case .signingIn: DockButton(title: "Cancel", glyph: nil, metrics: .confirm, tone: .ctrl, action: store.cancelSignIn)
        default: GoogleSignInButton(action: store.signIn)
        }
    }
}

/// Signed in: the header, the grid for the chosen view, and the calendars menu over both.
private struct CalendarMain: View {
    var store: CalendarStore

    var body: some View {
        VStack(spacing: 0) {
            CalendarHeader(store: store).padding(.top, Geo.Chrome.subNavTop)
            Group {
                switch store.mode {
                case .month: CalendarMonthView(store: store)
                case .week, .day: CalendarTimeGrid(store: store)
                }
            }
            .padding(.top, Geo.Chrome.contentTop)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .topTrailing) { CalendarsMenu(store: store) }
    }
}

/// ‹ › Today · title · Month / Week / Day · ↻ · calendars.
private struct CalendarHeader: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.SubTab.navGap) {
            StepButton(label: "Previous", turns: 90) { store.go(.previous) }
            StepButton(label: "Next", turns: -90) { store.go(.next) }
            Button { store.go(.today) } label: {
                Text("Today")
                    .font(Typo.ui(12.5, .semibold))
                    .foregroundStyle(t.text)
                    .padding(.horizontal, 12)
                    .frame(height: Geo.SubTab.height)
                    .background(Capsule().fill(t.ctrl))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Text(store.title)
                .font(Typo.display(15))
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.leading, 6)
            Spacer(minLength: 8)
            SubTabs(items: CalendarMode.allCases.map { SubTabItem($0.rawValue, $0.label) }, selection: store.mode.rawValue) {
                store.setMode(CalendarMode(rawValue: $0) ?? .week)
            }
            RefreshButton(store: store)
            CalendarsButton(store: store)
        }
        .frame(height: Geo.SubTab.height)
    }
}

/// `chevronDown` turned to point left (90°) or right (-90°).
private struct StepButton: View {
    var label: String
    var turns: Double
    var action: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            Icon(.chevronDown, size: 14, stroke: 2.6)
                .rotationEffect(.degrees(turns))
                .foregroundStyle(t.text2)
                .frame(width: Geo.SubTab.height, height: Geo.SubTab.height)
                .background(Circle().fill(t.ctrl))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct RefreshButton: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t

    var body: some View {
        Button { Task { await store.refresh(force: true) } } label: {
            Group {
                if store.loading > 0 { Spinner(size: 14) } else { Icon(.refresh, size: 14) }
            }
            .foregroundStyle(t.text2)
            .frame(width: Geo.SubTab.height, height: Geo.SubTab.height)
            .background(Circle().fill(t.ctrl))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh")
    }
}

/// `▢ 3 ▾`: how many calendars are shown, and the way to change that.
private struct CalendarsButton: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t

    var body: some View {
        let open = store.calendarsMenuOpen
        Button(action: store.toggleCalendarsMenu) {
            HStack(spacing: 6) {
                Icon(.calendar, size: 14)
                Text("\(store.shownCalendars.count)").font(Typo.ui(12.5, .semibold))
                Icon(.chevronDown, size: 10, stroke: 2.8)
            }
            .foregroundStyle(open ? t.panel : t.text)
            .padding(.horizontal, 11)
            .frame(height: Geo.SubTab.height)
            .background(Capsule().fill(open ? t.text : t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendars")
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}

/// Dropdown under the calendars button: one tick box per calendar in its own colour, then the account and Sign out.
/// Drawn over the whole screen, like the Notes menus, so an outside click can close it.
private struct CalendarsMenu: View {
    var store: CalendarStore
    @Environment(\.tokens) private var t

    var body: some View {
        if store.calendarsMenuOpen {
            // One explicit ZStack: two siblings in a conditional would be centred, not pinned to the button's corner.
            ZStack(alignment: .topTrailing) {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: store.closeMenus)
                menu.padding(.top, Geo.Chrome.subNavTop + Geo.SubTab.height + 6)
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            Text("CALENDARS")
                .font(Typo.ui(10.5, .bold))
                .tracking(1)
                .foregroundStyle(t.faint)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Geo.Menu.headerHeight, maxHeight: Geo.Menu.headerHeight, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, 6)
            let rows = VStack(spacing: 0) { ForEach(store.calendars) { row($0) } }
            if store.calendars.isEmpty {
                Text("Loading…").font(Typo.ui(Geo.Menu.font)).foregroundStyle(t.faint).frame(height: Geo.Menu.rowHeight)
            } else if store.calendars.count > Geo.Cal.menuRows {
                DockScroll { rows }.frame(height: CGFloat(Geo.Cal.menuRows) * Geo.Menu.rowHeight)
            } else {
                rows
            }
            if let email = store.accountEmail { account(email) }
        }
        .padding(Geo.Menu.padding + 1)
        .frame(width: Geo.Cal.menuWidth)
        .background {
            RoundedRectangle(cornerRadius: Geo.Menu.radius).fill(t.pop)
                .shadow(color: t.popShadow, radius: Geo.Menu.shadow.radius, y: Geo.Menu.shadow.y)
        }
        .overlay(RoundedRectangle(cornerRadius: Geo.Menu.radius).strokeBorder(t.border, lineWidth: 1))
    }

    private func row(_ calendar: CalendarInfo) -> some View {
        let on = store.isShown(calendar)
        let color = Color(hex: calendar.color)
        return Button { store.toggle(calendar.id) } label: {
            HStack(spacing: Geo.Menu.rowGap) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(on ? color : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: on ? 0 : 1.5))
                    .overlay { if on { Icon(.check, size: 10, stroke: 3.6).foregroundStyle(Self.checkColor(calendar.color)) } }
                    .frame(width: 14, height: 14)
                Text(calendar.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(Typo.ui(Geo.Menu.font, .medium))
            .foregroundStyle(t.text)
            .padding(.horizontal, Geo.Menu.rowPadX)
            .frame(height: Geo.Menu.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func account(_ email: String) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.line).frame(height: 1).padding(.vertical, 5)
            Text(email)
                .font(Typo.ui(11.5))
                .foregroundStyle(t.faint)
                .lineLimit(1)
                .padding(.horizontal, Geo.Menu.rowPadX)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            Button(action: store.askSignOut) {
                HStack(spacing: Geo.Menu.rowGap) {
                    Icon(.power, size: 13)
                    Text("Sign out")
                }
                .font(Typo.ui(Geo.Menu.font, .medium))
                .foregroundStyle(t.text2)
                .padding(.horizontal, Geo.Menu.rowPadX)
                .frame(maxWidth: .infinity, minHeight: Geo.Menu.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Black on light calendar colours, white on dark ones.
    private static func checkColor(_ hex: UInt32) -> Color {
        let (r, g, b) = (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
        return 0.299 * r + 0.587 * g + 0.114 * b > 160 ? .black : .white
    }
}

/// Google's own button spec (developers.google.com/identity/branding-guidelines): the official multicolour G on white,
/// the Light or Dark variant to match the theme, "Sign in with Google". The G is Google's artwork, unaltered.
private struct GoogleSignInButton: View {
    var action: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        let dark = t.isDark
        Button(action: action) {
            HStack(spacing: Geo.Cal.googleGap) {
                Image("GoogleG").resizable().interpolation(.high).frame(width: Geo.Cal.googleIcon, height: Geo.Cal.googleIcon)
                Text("Sign in with Google").font(Typo.ui(14, .medium))
            }
            .foregroundStyle(dark ? Color(hex: 0xE3E3E3) : Color(hex: 0x1F1F1F))
            .padding(.leading, Geo.Cal.googlePad.leading)
            .padding(.trailing, Geo.Cal.googlePad.trailing)
            .frame(height: Geo.Cal.googleHeight)
            .background(Capsule().fill(dark ? Color(hex: 0x131314) : .white))
            .overlay(Capsule().strokeBorder(dark ? Color(hex: 0x8E918F) : Color(hex: 0x747775), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sign in with Google")
    }
}
