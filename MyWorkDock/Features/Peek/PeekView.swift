import SwiftUI

// Peek (hover): two ears hugging their content around the hardware notch. Black in dark theme, light in light.
// DESIGN_SPEC §4; markup from Prototype.dc.html lines 56–88.

struct PeekExtents: Equatable {
    var left: CGFloat
    var right: CGFloat
}

enum PeekMetrics {
    /// Measures the real ear views (not an estimate), so the shell hugs them exactly.
    @MainActor
    static func measure(_ data: PeekData) -> PeekExtents {
        func width<V: View>(_ v: V) -> CGFloat {
            NSHostingView(rootView: v.fixedSize()).fittingSize.width.rounded()
        }
        return PeekExtents(left: width(PeekLeftEar(data: data)), right: width(PeekRightEar(data: data)))
    }

    /// claudex off: one ear on the right of the notch, with the hint.
    @MainActor
    static let hintExtents = PeekExtents(left: 0, right: NSHostingView(rootView: PeekHintEar().fixedSize()).fittingSize.width.rounded())
}

struct PeekView: View {
    var data: PeekData
    var extents: PeekExtents
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            PeekLeftEar(data: data)
                .frame(width: extents.left, alignment: .trailing)
            Color.clear.frame(width: Geo.keepOutWidth)
            PeekRightEar(data: data)
                .frame(width: extents.right, alignment: .leading)
        }
        .foregroundStyle(t.text)
        .frame(width: Geo.keepOutWidth + extents.left + extents.right, height: Geo.peek.height)
        .contentShape(Rectangle())
    }
}

/// Peek while the claudex menu is off: nothing to show, so it invites a click.
struct PeekHintView: View {
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Geo.keepOutWidth)
            PeekHintEar().frame(width: PeekMetrics.hintExtents.right, alignment: .leading)
        }
        .foregroundStyle(t.text)
        .frame(width: Geo.keepOutWidth + PeekMetrics.hintExtents.right, height: Geo.peek.height)
        .contentShape(Rectangle())
    }
}

struct PeekHintEar: View {
    @Environment(\.tokens) private var t

    var body: some View {
        Text("Tap to see magic ✨")
            .font(Typo.ui(Geo.Peek.nameSize, .bold))
            .foregroundStyle(t.text2)
            .lineLimit(1)
            .padding(.leading, Geo.Peek.rightPadding.leading)
            .padding(.trailing, Geo.Peek.rightPadding.trailing)
    }
}

struct PeekLeftEar: View {
    var data: PeekData
    @Environment(\.tokens) private var t

    private var fg: Color { data.isPool ? (t.isDark ? Fixed.poolFg : Fixed.poolFgLight) : t.boot }
    private var bg: Color { data.isPool ? Fixed.poolBg : Fixed.ssoBg }

    var body: some View {
        HStack(spacing: Geo.Peek.leftGap) {
            VStack(alignment: .trailing, spacing: Geo.Peek.textGap) {
                Text(data.name)
                    .font(Typo.ui(Geo.Peek.nameSize, .bold))
                    .lineLimit(1)
                HStack(spacing: Geo.Peek.modeDotGap) {
                    Circle().fill(fg).frame(width: Geo.Peek.modeDot, height: Geo.Peek.modeDot)
                    Text(data.isPool ? "POOL" : "SSO")
                        .font(Typo.ui(Geo.Peek.modeSize, .heavy))
                        .tracking(Geo.Peek.modeTracking)
                }
                .foregroundStyle(fg)
            }
            Text(data.initial)
                .font(Typo.ui(12, .heavy))
                .foregroundStyle(fg)
                .frame(width: Geo.Peek.avatar, height: Geo.Peek.avatar)
                .background(Circle().fill(bg))
        }
        .padding(.leading, Geo.Peek.leftPadding.leading)
        .padding(.trailing, Geo.Peek.leftPadding.trailing)
    }
}

struct PeekRightEar: View {
    var data: PeekData

    var body: some View {
        HStack(spacing: Geo.Peek.unitGap) {
            ForEach(data.bars) { PeekRingUnit(bar: $0) }
        }
        .padding(.leading, Geo.Peek.rightPadding.leading)
        .padding(.trailing, Geo.Peek.rightPadding.trailing)
    }
}

private struct PeekRingUnit: View {
    var bar: PeekBar
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.Peek.ringToTextGap) {
            RingGauge(percent: bar.percent)
            VStack(alignment: .leading, spacing: Geo.Peek.textGap) {
                Text(bar.label)
                    .font(Typo.ui(Geo.Peek.labelSize, .heavy))
                    .tracking(Geo.Peek.modeTracking)
                    .foregroundStyle(bar.isHot ? (t.isDark ? Fixed.peekLabelHot : t.red) : t.faint)
                reset
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var reset: some View {
        let font = Typo.ui(Geo.Peek.resetSize, .semibold)
        if bar.percent == nil {
            Text("no reading").font(font).foregroundStyle(t.text2)
        } else if let r = bar.reset {
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(Typo.ui(Geo.Peek.resetIcon, .semibold))
                Text(r).font(font)
            }
            .foregroundStyle(t.text2)
        } else {
            Text("idle").font(font).foregroundStyle(t.text2)
        }
    }
}
