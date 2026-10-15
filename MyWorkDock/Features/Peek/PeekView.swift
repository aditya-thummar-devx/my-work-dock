import SwiftUI

// Peek (hover): two ears hugging their content around the hardware notch. Black in dark theme, light in light.
// DESIGN_SPEC §4; markup from Prototype.dc.html lines 56–88.

struct PeekExtents: Equatable {
    var left: CGFloat
    var right: CGFloat
}

enum PeekMetrics {
    @MainActor
    private static func width<V: View>(_ v: V) -> CGFloat {
        NSHostingView(rootView: v.fixedSize()).fittingSize.width.rounded()
    }

    /// Measures the real ear views (not an estimate), so the shell hugs them exactly.
    @MainActor
    static func measure(_ data: PeekData) -> PeekExtents {
        PeekExtents(left: width(PeekLeftEar(data: data)), right: width(PeekRightEar(data: data)))
    }

    /// Nothing to show: one ear on the right of the notch, with the hint.
    @MainActor
    static let hintExtents = PeekExtents(left: 0, right: width(PeekHintEar()))

    /// Counts on the left, the IP on the right; a side with nothing to show is 0 wide.
    /// Cached per value: the shell reads this on every pointer move.
    @MainActor private static var infoCache: [PeekInfo: PeekExtents] = [:]

    @MainActor
    static func measure(_ info: PeekInfo) -> PeekExtents {
        if let hit = infoCache[info] { return hit }
        let extents = PeekExtents(left: info.hasLeft ? width(PeekInfoLeftEar(info: info)) : 0,
                                  right: info.ip.map { width(PeekInfoRightEar(ip: $0)) } ?? 0)
        infoCache[info] = extents
        return extents
    }
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

/// Peek while claudex is off: the TODO and clipboard counts on the left of the notch, the Local IP on its right.
/// A part with nothing to show is left out and the rest stay on their side.
struct PeekInfoView: View {
    var info: PeekInfo
    @Environment(\.tokens) private var t

    var body: some View {
        let e = PeekMetrics.measure(info)
        HStack(spacing: 0) {
            if info.hasLeft { PeekInfoLeftEar(info: info).frame(width: e.left, alignment: .trailing) }
            Color.clear.frame(width: Geo.keepOutWidth)
            if let ip = info.ip { PeekInfoRightEar(ip: ip).frame(width: e.right, alignment: .leading) }
        }
        .foregroundStyle(t.text)
        .frame(width: Geo.keepOutWidth + e.left + e.right, height: Geo.peek.height)
        .contentShape(Rectangle())
    }
}

/// Peek with nothing to show: it invites a click.
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
            .foregroundStyle(t.ink)
            .lineLimit(1)
            .padding(.leading, Geo.Peek.rightPadding.leading)
            .padding(.trailing, Geo.Peek.rightPadding.trailing)
    }
}

/// A small caption over its value, like the claudex rings: `TODO` over `○ 3  ✓ 2`. The caption takes the unit's colour.
private struct PeekUnit<Content: View>: View {
    var label: String
    var color: Color
    @ViewBuilder var content: Content
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Peek.textGap) {
            Text(label)
                .font(Typo.ui(Geo.Peek.labelSize, .heavy))
                .tracking(Geo.Peek.modeTracking)
                .foregroundStyle(color)
            content
        }
        .fixedSize()
    }
}

/// An icon and its count, both in `color`.
private struct PeekCount: View {
    var glyph: Glyph
    var value: Int
    var color: Color

    var body: some View {
        HStack(spacing: Geo.Peek.countGap) {
            Icon(glyph, size: Geo.Peek.countIcon, stroke: glyph == .check ? 3 : 2.2)
            Text("\(value)").font(Typo.ui(Geo.Peek.countSize, .bold))
        }
        .foregroundStyle(color)
    }
}

/// Peek colours, from the theme so both themes stay readable: TODO is orange (waiting) and green (done), clips are
/// lavender with a red pin, the IP is cyan, as the pool badge is.
struct PeekInfoLeftEar: View {
    var info: PeekInfo
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.Peek.unitGap) {
            if let todo = info.todo {
                PeekUnit(label: "TODO", color: t.orange) {
                    HStack(spacing: Geo.Peek.countPairGap) {
                        PeekCount(glyph: .ring, value: todo.left, color: t.orange)
                        PeekCount(glyph: .check, value: todo.done, color: t.green)
                    }
                }
            }
            if let clips = info.clips {
                PeekUnit(label: "CLIPS", color: t.boot) {
                    HStack(spacing: Geo.Peek.countPairGap) {
                        PeekCount(glyph: .clipboard, value: clips.total, color: t.boot)
                        PeekCount(glyph: .pin, value: clips.pinned, color: t.red)
                    }
                }
            }
        }
        .padding(.leading, Geo.Peek.leftPadding.leading)
        .padding(.trailing, Geo.Peek.leftPadding.trailing)
    }
}

struct PeekInfoRightEar: View {
    var ip: String
    @Environment(\.tokens) private var t

    var body: some View {
        let cyan = t.isDark ? Fixed.poolFg : Fixed.poolFgLight
        PeekUnit(label: "IP", color: cyan) {
            Text(ip).font(Typo.mono(Geo.Peek.countSize, .semibold)).foregroundStyle(cyan)
        }
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
