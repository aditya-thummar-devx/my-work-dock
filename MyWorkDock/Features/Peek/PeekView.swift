import SwiftUI

// Peek (hover): two ears hugging their content around the hardware notch. Always on black.
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
}

struct PeekView: View {
    var data: PeekData
    var extents: PeekExtents

    var body: some View {
        HStack(spacing: 0) {
            PeekLeftEar(data: data)
                .frame(width: extents.left, alignment: .trailing)
            Color.clear.frame(width: Geo.keepOutWidth)
            PeekRightEar(data: data)
                .frame(width: extents.right, alignment: .leading)
        }
        .foregroundStyle(Fixed.peekText)
        .frame(width: Geo.keepOutWidth + extents.left + extents.right, height: Geo.peek.height)
        .contentShape(Rectangle())
    }
}

struct PeekLeftEar: View {
    var data: PeekData

    private var fg: Color { data.isPool ? Fixed.poolFg : Fixed.ssoFg }
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

    var body: some View {
        HStack(spacing: Geo.Peek.ringToTextGap) {
            RingGauge(percent: bar.percent)
            VStack(alignment: .leading, spacing: Geo.Peek.textGap) {
                Text(bar.label)
                    .font(Typo.ui(Geo.Peek.labelSize, .heavy))
                    .tracking(Geo.Peek.modeTracking)
                    .foregroundStyle(bar.isHot ? Fixed.peekLabelHot : Fixed.peekLabel)
                reset
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var reset: some View {
        let font = Typo.ui(Geo.Peek.resetSize, .semibold)
        if bar.percent == nil {
            Text("no reading").font(font).foregroundStyle(Fixed.peekReset)
        } else if let r = bar.reset {
            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(Typo.ui(Geo.Peek.resetIcon, .semibold))
                Text(r).font(font)
            }
            .foregroundStyle(Fixed.peekReset)
        } else {
            Text("idle").font(font).foregroundStyle(Fixed.peekReset)
        }
    }
}
