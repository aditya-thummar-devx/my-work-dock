import SwiftUI

/// Live activity: "Booting <sim>" with a tint progress bar. Prototype.dc.html lines 91–104.
/// Booting reports no progress, so the bar eases toward full over a typical boot instead of the prototype's fake 2.4 s fill.
struct LiveActivityView: View {
    var name: String

    @Environment(\.tokens) private var t
    @Environment(\.entrance) private var entrance
    @Environment(\.liveProgress) private var progressOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fill: CGFloat = 0
    @State private var dim = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: Geo.Live.iconGap) {
                    Image(systemName: "power")
                        .font(.system(size: Geo.Live.icon, weight: .semibold))
                        .opacity(entrance && dim ? 0.35 : 1)
                    Text("Booting")
                }
                .foregroundStyle(t.accent)
                Spacer()
                Text(name)
            }
            .font(Typo.ui(Geo.Live.textSize, .semibold))
            .frame(height: Geo.Live.topRowHeight)
            Spacer(minLength: 0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Fixed.liveTrack)
                    Capsule().fill(t.accent).frame(width: geo.size.width * (progressOverride ?? fill))
                }
            }
            .frame(height: Geo.Live.barHeight)
        }
        .foregroundStyle(Fixed.liveText)
        .padding(.horizontal, Geo.Live.paddingX)
        .padding(.bottom, Geo.Live.paddingBottom)
        .frame(width: Geo.live.width, height: Geo.live.height)
        .onAppear {
            guard entrance else { return }
            if reduceMotion { fill = 0.5; return } // no fill animation, no pulse
            withAnimation(.easeOut(duration: Geo.liveFillDuration)) { fill = 0.95 }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}
