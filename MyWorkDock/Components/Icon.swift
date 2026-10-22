import SwiftUI

/// The designs' icons, ported from the inline SVGs in `design/Prototype.dc.html` (24 × 24 viewBox, round caps and joins).
/// Stroke width is part of the call site in the designs (2 – 3.6), so `Icon` takes it as a parameter and
/// each glyph carries the most common one as its default.
enum Glyph {
    case clipboard, notes, terminal, gauge, phone, tablet, pin, sliders, search, plus, refresh, close, check, copy, pencil, trash
    case wifi, arrows, chevronDown, play, stop, power, warning, monitor, arrowLeft, moon, sun, triangle, funnel, tag, globe, ring
    case calendar
    case clock, mapPin, video, users, bell, link, text, paperclip, recur, question, lock
    case gear, eye, info

    fileprivate enum Part {
        case path(String)
        case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
    }

    fileprivate var parts: [Part] {
        switch self {
        case .clipboard: [.rect(x: 5, y: 4, w: 14, h: 17, rx: 2.5), .path("M9 4V2.5h6V4"), .path("M9 11h6M9 15h4")]
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
        case .ring: [.circle(cx: 12, cy: 12, r: 8.5)]
        case .calendar: [.rect(x: 3, y: 5, w: 18, h: 16, rx: 3), .path("M3 10h18M8 3v4M16 3v4")]
        case .clock: [.circle(cx: 12, cy: 12, r: 9), .path("M12 7v5l3 2")]
        case .mapPin: [.path("M21 10c0 7-9 13-9 13c0 0-9-6-9-13a9 9 0 0 1 18 0z"), .circle(cx: 12, cy: 10, r: 3)]
        case .video: [.rect(x: 2, y: 5, w: 14, h: 14, rx: 2.5), .path("M22 8l-6 4 6 4z")]
        case .users: [.path("M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"), .circle(cx: 9, cy: 7, r: 4), .path("M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75")]
        case .bell: [.path("M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18c0 0-3-2-3-9"), .path("M13.73 21a2 2 0 0 1-3.46 0")]
        case .link: [.path("M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"), .path("M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71")]
        case .text: [.path("M17 10H3M21 6H3M21 14H3M17 18H3")]
        case .paperclip: [.path("M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48")]
        case .recur: [.path("M17 1l4 4-4 4M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4M21 13v2a4 4 0 0 1-4 4H3")]
        case .question: [.circle(cx: 12, cy: 12, r: 10), .path("M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3M12 17h.01")]
        case .lock: [.rect(x: 5, y: 11, w: 14, h: 10, rx: 2.5), .path("M8 11V8a4 4 0 0 1 8 0v3")]
        case .gear: [.circle(cx: 12, cy: 12, r: 3), .path("M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z")]
        case .eye: [.path("M2 12C5 7 8.5 5 12 5C15.5 5 19 7 22 12C19 17 15.5 19 12 19C8.5 19 5 17 2 12Z"), .circle(cx: 12, cy: 12, r: 3)]
        case .info: [.circle(cx: 12, cy: 12, r: 10), .path("M12 16v-4M12 8h.01")]
        }
    }

    /// Solid glyphs (`fill="currentColor"` in the designs) instead of stroked.
    fileprivate var filled: Bool { self == .play || self == .stop || self == .triangle }

    var defaultStroke: CGFloat {
        switch self {
        case .terminal, .gauge, .plus, .arrowLeft: 2.4
        case .pin, .sliders, .gear: 2
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
