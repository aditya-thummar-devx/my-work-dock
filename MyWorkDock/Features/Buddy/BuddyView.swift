import SwiftUI

/// The buddy in the idle notch's right ear (v3 change 8). The container draws it only while the notch is idle: a peek, the live
/// activity and the open panel replace it. Its animations are Lottie files (BuddyAsset), tinted with the user's tint (`Tokens.buddy`:
/// the shell is the theme's, so on the light one the tint is darkened to stay seen).
struct BuddyView: View {
    var prefs: BuddyPrefs
    /// What to play: `prefs` through the library (`BuddyAsset.init(_:library:)`).
    var asset: BuddyAsset
    /// The first-launch hint is up: the buddy bobs, for a few bobs.
    var bobbing = false
    /// The screen is asleep or the session is away: nothing moves.
    var paused = false
    @Environment(\.tokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticRender) private var staticRender
    @Environment(\.entrance) private var entrance
    /// False until the view is up: the buddy fades in rather than popping into a shell that is still shrinking around it.
    @State private var arrived = false
    /// The hint's bob: up and down a few times, then at rest.
    @State private var lifted = false

    private static let fade = Animation.easeInOut(duration: Geo.Buddy.fadeIn.duration).delay(Geo.Buddy.fadeIn.delay)

    var body: some View {
        // Reduce Motion in macOS forces Still. Snapshots hold the first frame: ImageRenderer cannot draw an AppKit view.
        let motion = reduceMotion || paused ? BuddyMotion.still : prefs.motion
        let bobs = bobbing && motion != .still
        Group {
            if motion == .still || staticRender {
                BuddyStillView(asset: asset, tint: t.buddy)
            } else {
                LottieBuddy(asset: asset, tint: t.buddy, speed: asset.speed(for: motion))
            }
        }
        .offset(y: lifted ? -Geo.Buddy.bob : 0)
        .frame(width: Geo.Buddy.ear, height: Geo.Buddy.height)
        .opacity(arrived || !entrance ? 1 : 0)
        .animation(Self.fade, value: arrived)
        .accessibilityHidden(true) // decorative: the notch itself is the button
        .onAppear { arrived = true }
        .task(id: bobs) { await bob(bobs) }
    }

    /// The hint stays until the first hover, however long: the bob runs `bobFor` seconds, then the buddy rests.
    private func bob(_ on: Bool) async {
        guard on else { lifted = false; return }
        let half = Geo.Buddy.bobPeriod / 2
        do {
            for _ in 0..<Int(Geo.Buddy.bobFor / Geo.Buddy.bobPeriod) {
                withAnimation(.easeInOut(duration: half)) { lifted = true }
                try await Task.sleep(for: .seconds(half))
                withAnimation(.easeInOut(duration: half)) { lifted = false }
                try await Task.sleep(for: .seconds(half))
            }
        } catch {
            lifted = false
        }
    }
}

/// "👋 I live in your notch. Hover me." under the buddy on first launch. Fixed colours: it is a light bubble on any theme.
struct BuddyHint: View {
    @Environment(\.entrance) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.staticRender) private var staticRender
    @Environment(\.tokens) private var t
    @State private var shown = false

    private static let fill = Color(hex: 0xF5F5F7)
    private static let text = Color(hex: 0x111114)
    private static let spring = Animation.timingCurve(Geo.Buddy.Hint.enter.curve.x1, Geo.Buddy.Hint.enter.curve.y1,
                                                      Geo.Buddy.Hint.enter.curve.x2, Geo.Buddy.Hint.enter.curve.y2,
                                                      duration: Geo.Buddy.Hint.enter.duration)

    var body: some View {
        let on = shown || !enabled
        VStack(alignment: .leading, spacing: 0) {
            Triangle().fill(Self.fill)
                .frame(width: Geo.Buddy.Hint.arrow.width, height: Geo.Buddy.Hint.arrow.height)
                .padding(.leading, Geo.Buddy.Hint.arrowCentre - Geo.Buddy.Hint.arrow.width / 2)
            HStack(spacing: Geo.Buddy.Hint.contentGap) {
                wave
                Text(Geo.Buddy.Hint.text).font(Typo.ui(Geo.Buddy.Hint.font, .semibold)).foregroundStyle(Self.text)
            }
            .padding(.horizontal, Geo.Buddy.Hint.padX)
            .padding(.vertical, Geo.Buddy.Hint.padY)
            .background(RoundedRectangle(cornerRadius: Geo.Buddy.Hint.radius).fill(Self.fill))
        }
        .fixedSize()
        .opacity(on ? 1 : 0)
        .scaleEffect(on || reduceMotion ? 1 : 0.9)
        .offset(y: on || reduceMotion ? 0 : -6)
        .animation(reduceMotion ? nil : Self.spring.delay(Geo.Buddy.fadeIn.delay), value: on) // with the buddy it points at
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }

    /// The 👋 waves at the lively pace whatever Settings › Motion says, a few times; it is a greeting, not the buddy. Its file has a
    /// margin the wave swings into, taken back here so the text sits where the glyph's own box ends.
    @ViewBuilder private var wave: some View {
        let asset = BuddyAsset.hello
        Group {
            if reduceMotion || staticRender {
                BuddyStillView(asset: asset, tint: t.accent)
            } else {
                LottieBuddy(asset: asset, tint: t.accent, loops: .repeat(Geo.Buddy.Hint.waveLoops))
            }
        }
        .frame(width: asset.size.width, height: asset.size.height)
        .padding(-asset.margin)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
