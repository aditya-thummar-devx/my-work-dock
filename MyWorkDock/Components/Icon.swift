import SwiftUI

/// The designs' icons, ported from the inline SVGs in `design/Prototype.dc.html` (24 × 24 viewBox, round caps and joins).
/// Stroke width is part of the call site in the designs (2 – 3.6), so `Icon` takes it as a parameter and
/// each glyph carries the most common one as its default.
enum Glyph {
    case notes, terminal, gauge, phone, tablet, pin, sliders, search, plus, refresh, close, check, copy, pencil, trash
    case wifi, arrows, chevronDown, play, stop, power, warning, monitor, arrowLeft, moon, sun, triangle, funnel, tag, globe

    fileprivate enum Part {
        case path(String)
        case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
    }

    fileprivate var parts: [Part] {
        switch self {
        case .notes: [.path("M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"), .path("M14 3v5h5M9 13h6M9 17h4")]
        case .terminal: [.path("M4 17l6-5-6-5"), .path("M12 19h8")]
        case .gauge: [.path("M4 16a8 8 0 1 1 16 0"), .path("M12 16l4-5")]
        case .phone: [.rect(x: 7, y: 2, w: 10, h: 20, rx: 2.5), .path("M11 18h2")]
        case .tablet: [.rect(x: 4, y: 2.5, w: 16, h: 19, rx: 2.5), .path("M11 18.5h2")]
        case .pin: [.path("M12 17v5M8 3h8l-1 6 3 4H6l3-4z")]
        case .sliders: [.path("M4 7h10M18 7h2M4 17h4M12 17h8"), .circle(cx: 16, cy: 7, r: 2), .circle(cx: 10, cy: 17, r: 2)]
        case .search: [.circle(cx: 11, cy: 11, r: 7), .path("M20 20l-3.5-3.5")]
        case .plus: [.path("M12 5v14M5 12h14")]
        case .refresh: [.path("M20 11a8 8 0 1 0-2.3 5.7"), .path("M20 4v7h-7")]
        case .close: [.path("M6 6l12 12M18 6 6 18")]
        case .check: [.path("M5 12l5 5 9-10")]
        case .copy: [.rect(x: 9, y: 9, w: 11, h: 11, rx: 2), .path("M5 15V6a2 2 0 0 1 2-2h8")]
        case .pencil: [.path("M4 20h4L19 9l-4-4L4 16z"), .path("M13.5 6.5l4 4")]
        case .trash: [.path("M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13")]
        case .wifi: [.path("M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"), .path("M12 19.5h.01")]
        case .arrows: [.path("M7 7h11l-3-3M17 17H6l3 3")]
        case .chevronDown: [.path("M6 9l6 6 6-6")]
        case .play: [.path("M7 4.5v15l12-7.5z")]
        case .stop: [.rect(x: 4, y: 4, w: 16, h: 16, rx: 3)]
        case .power: [.path("M12 3v8"), .path("M6.3 6.3a8 8 0 1 0 11.4 0")]
        case .warning: [.path("M12 4l9 16H3z"), .path("M12 10v4M12 17h.01")]
        case .monitor: [.rect(x: 3, y: 4, w: 18, h: 12, rx: 2), .path("M8 20h8M12 16v4")]
        case .arrowLeft: [.path("M19 12H5M11 6l-6 6 6 6")]
        case .moon: [.path("M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z")]
        case .sun: [.circle(cx: 12, cy: 12, r: 4), .path("M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4")]
        case .triangle: [.path("M6 4l14 8-14 8z")]
        case .funnel: [.path("M4 5h16l-6 7.5V19l-4 1.5v-8z")]
        case .tag: [.path("M3 12V4h8l10 10-8 8z"), .circle(cx: 7.5, cy: 7.5, r: 1.4)]
        case .globe: [.circle(cx: 12, cy: 12, r: 9), .path("M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18")]
        }
    }

    /// Solid glyphs (`fill="currentColor"` in the designs) instead of stroked.
    fileprivate var filled: Bool { self == .play || self == .stop || self == .triangle }

    var defaultStroke: CGFloat {
        switch self {
        case .terminal, .gauge, .plus, .arrowLeft: 2.4
        case .pin, .sliders: 2
        case .funnel, .tag: 2.3
        case .pencil, .trash: 2.1
        default: 2.2
        }
    }
}

private struct GlyphShape: Shape {
    var glyph: Glyph

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for part in glyph.parts {
            switch part {
            case .path(let d): p.addPath(SVGPath.parse(d))
            case .rect(let x, let y, let w, let h, let rx): p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: rx, height: rx))
            case .circle(let cx, let cy, let r): p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            }
        }
        let s = rect.width / 24
        return p.applying(CGAffineTransform(scaleX: s, y: s)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A `size` × `size` icon drawn in the current foreground style.
struct Icon: View {
    var glyph: Glyph
    var size: CGFloat = 14
    var stroke: CGFloat?

    init(_ glyph: Glyph, size: CGFloat = 14, stroke: CGFloat? = nil) {
        self.glyph = glyph
        self.size = size
        self.stroke = stroke
    }

    var body: some View {
        Group {
            if glyph.filled {
                GlyphShape(glyph: glyph).fill(style: FillStyle())
            } else {
                GlyphShape(glyph: glyph)
                    .stroke(style: StrokeStyle(lineWidth: (stroke ?? glyph.defaultStroke) * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
