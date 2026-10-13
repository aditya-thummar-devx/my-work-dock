import SwiftUI

extension Geo {
    enum GaugeRow {
        static let gap: CGFloat = 8
        static let labelWidth: CGFloat = 50
        static let labelSize: CGFloat = 11.5
        static let percentWidth: CGFloat = 36
        static let percentSize: CGFloat = 11.5
        static let resetWidth: CGFloat = 86
        static let resetSize: CGFloat = 11
        /// Bar heights: usage cards 8, pool cards 14, details usage split 12.
        static let barUsage: CGFloat = 8
        static let barPool: CGFloat = 14
        static let barSplit: CGFloat = 12
    }
}

/// Pill track with a pill fill. Colour follows the gauge rule (< 50 % green, 50–79 % amber, ≥ 80 % red).
struct BarGauge: View {
    var percent: Int
    var height: CGFloat = Geo.GaugeRow.barUsage
    @Environment(\.tokens) private var t

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.track)
                Capsule().fill(t.gaugeColor(percent)).frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// `session  [bar]  20%  2:39pm` row used by usage and pool cards.
struct GaugeRow: View {
    var label: String
    var percent: Int
    var reset: String
    var barHeight: CGFloat = Geo.GaugeRow.barUsage
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.GaugeRow.gap) {
            Text(label)
                .font(Typo.ui(Geo.GaugeRow.labelSize))
                .foregroundStyle(t.muted)
                .frame(width: Geo.GaugeRow.labelWidth, alignment: .leading)
            BarGauge(percent: percent, height: barHeight)
            Text("\(percent)%")
                .font(Typo.mono(Geo.GaugeRow.percentSize, .bold))
                .foregroundStyle(t.text)
                .frame(width: Geo.GaugeRow.percentWidth, alignment: .trailing)
            Text(reset)
                .font(Typo.ui(Geo.GaugeRow.resetSize))
                .foregroundStyle(t.faint)
                .lineLimit(1)
                .frame(width: Geo.GaugeRow.resetWidth, alignment: .leading)
        }
    }
}

/// 30 pt ring (r 15 in a 36 viewBox, stroke 4), starts at 12 o'clock, round cap except at 0 %.
/// Used by the peek, which follows the shell: black in dark theme, light in light theme.
struct RingGauge: View {
    var percent: Int?
    @Environment(\.tokens) private var t

    var body: some View {
        let k = Geo.Peek.ring / Geo.Peek.ringViewBox
        let p = Double(percent ?? 0) / 100
        let color = percent.map { t.gaugeColor($0) } ?? Fixed.runningDot
        ZStack {
            ZStack {
                Circle().stroke(t.isDark ? Fixed.peekRingTrack : t.track, lineWidth: Geo.Peek.ringStroke * k)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(color, style: StrokeStyle(lineWidth: Geo.Peek.ringStroke * k, lineCap: p > 0 ? .round : .butt))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 2 * Geo.Peek.ringRadius * k, height: 2 * Geo.Peek.ringRadius * k)
            Text(percent.map { "\($0)%" } ?? "—")
                .font(Typo.mono(Geo.Peek.percentSize, .heavy))
                .tracking(Geo.Peek.percentTracking)
        }
        .frame(width: Geo.Peek.ring, height: Geo.Peek.ring)
    }
}
