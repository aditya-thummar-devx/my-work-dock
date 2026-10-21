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
    }
}

/// My Calendar: fills the open panel between the top row and the footer. For now only the sign-in states.
struct CalendarScreen: View {
    var store: CalendarStore

    var body: some View {
        switch store.auth {
        case .signedIn(let email): SignedInHold(email: email, onSignOut: store.askSignOut).task { await store.verifySession() }
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

/// Until the calendar itself arrives: who is signed in, and a way out.
private struct SignedInHold: View {
    var email: String
    var onSignOut: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(spacing: Geo.Cal.gap) {
            Icon(.calendar, size: 26).foregroundStyle(t.muted)
            Text("You are signed in").font(Typo.display(18)).tracking(-0.4)
            Text(email).font(Typo.mono(12.5)).foregroundStyle(t.text2)
            Text("Your events show up here in the next update.").font(Typo.ui(13)).foregroundStyle(t.text2)
            DockButton(title: "Sign out", glyph: nil, metrics: .confirm, tone: .outline(nil), action: onSignOut).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
