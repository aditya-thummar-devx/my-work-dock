import SwiftUI

/// Original mascot designs (no existing characters), drawn in a 100×110 box with the seat on the
/// bottom edge so they sit on the Trash.
enum MascotKind: String, CaseIterable, Identifiable {
    case kunoichi, robot, cat, boo
    var id: String { rawValue }
    var name: String {
        switch self {
        case .kunoichi: "Kunoichi"
        case .robot: "Robot"
        case .cat: "Cat"
        case .boo: "Boo"
        }
    }
}

/// Parts that animate on their own.
private enum Part { case body, legSwing, eyes, mouthClosed, mouthOpen, tail, antenna }

private struct Layer {
    var part: Part
    var path: Path
    var fill: Color?
    var stroke: (Color, CGFloat)?
}

private func P(_ d: String) -> Path { SVGPath.parse(d) }
private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)) }
private func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path { ellipse(cx, cy, r, r) }
private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path { Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r) }
private func c(_ hex: UInt32) -> Color { Color(hex: hex) }

private func fill(_ p: Path, _ color: Color, _ part: Part = .body) -> Layer { Layer(part: part, path: p, fill: color) }
private func line(_ p: Path, _ color: Color, _ w: CGFloat, _ part: Part = .body) -> Layer { Layer(part: part, path: p, stroke: (color, w)) }

private func eyes(y: CGFloat, dx: CGFloat = 9, r: CGFloat = 3.2) -> [Layer] {
    [fill(ellipse(50 - dx, y, r, r * 1.25), c(0x1B1730), .eyes), fill(ellipse(50 + dx, y, r, r * 1.25), c(0x1B1730), .eyes),
     fill(circle(50 - dx + 1, y - 1.3, 1), .white, .eyes), fill(circle(50 + dx + 1, y - 1.3, 1), .white, .eyes)]
}

private func mouth(y: CGFloat, _ color: Color) -> [Layer] {
    [line(P("M46 \(y) C48.7 \(y + 2) 51.3 \(y + 2) 54 \(y - 0.5)"), color, 1.6, .mouthClosed),
     fill(ellipse(50, y + 1, 2.6, 2.2), color, .mouthOpen)]
}

private let kunoichi: [Layer] = {
    let skin = c(0xE7C6A8), face = c(0xF1D3B8), hair = c(0x1F6F78), suit = c(0x3B2D5C), red = c(0xD23C4A)
    return [
        fill(P("M50 92 C64 88 78 90 84 97 C86 100 83 104 78 103 C70 101 60 101 52 102 Z"), c(0x2B2140), .legSwing),
        fill(ellipse(83, 100, 6, 3.4), skin, .legSwing),
        line(P("M78 98 L88 98"), c(0x8A5A3C), 1.6, .legSwing),
        fill(P("M50 94 C38 90 24 92 18 100 C16 104 20 107 26 106 C34 104 44 104 52 105 Z"), c(0x33284D)),
        fill(ellipse(18, 103, 6, 3.4), skin),
        fill(P("M34 92 C33 78 37 66 50 64 C63 66 67 78 66 92 Z"), suit),
        fill(P("M36 74 L64 74 L62 80 L38 80 Z"), c(0xB8323F)),
        line(P("M60 76 C68 80 70 88 66 94"), c(0xB8323F), 5),
        line(P("M38 70 C30 78 34 88 44 91"), suit, 7),
        fill(circle(45, 91, 3.6), skin),
        fill(P("M38 63 C44 68 56 68 62 63 L60 69 C55 72 45 72 40 69 Z"), red),
        fill(circle(50, 42, 20), face),
        fill(P("M29 44 C27 24 40 16 52 17 C66 18 74 28 71 46 C70 38 66 33 62 31 C56 36 44 37 36 33 C32 36 30 40 29 44 Z"), hair),
        fill(P("M29 44 C28 54 31 60 35 62 L35 46 Z"), hair),
        fill(P("M71 46 C72 54 69 60 65 62 L65 46 Z"), hair),
        line(P("M62 20 L74 10"), red, 2.4),
        fill(circle(75, 9, 2.4), c(0xF5C542)),
        fill(P("M31 33 C42 29 58 29 69 33 L68 38 C57 34 43 34 32 38 Z"), c(0x26304A)),
        fill(rect(43, 30.5, 14, 6, 1.5), c(0xC9D1DC)),
    ] + eyes(y: 45) + [
        line(P("M38 39 L45 40.5 M62 39 L55 40.5"), c(0x1B1730), 1.4),
        fill(ellipse(38, 51, 3, 1.6), c(0xF2A3A3).opacity(0.6)),
        fill(ellipse(62, 51, 3, 1.6), c(0xF2A3A3).opacity(0.6)),
    ] + mouth(y: 53, c(0x7A2F3B))
}()

private let robot: [Layer] = {
    let metal = c(0xCFD6E0), dark = c(0x5B6475), leg = c(0x8B95A5), glow = c(0x4CC3FF)
    return [
        fill(rect(56, 92, 7, 14, 3), leg, .legSwing), fill(rect(54, 104, 11, 5, 2.5), dark, .legSwing),
        fill(rect(38, 92, 7, 14, 3), leg), fill(rect(36, 104, 11, 5, 2.5), dark),
        fill(rect(30, 64, 40, 32, 10), metal),
        fill(rect(40, 72, 20, 12, 3), glow.opacity(0.85)),
        line(P("M30 76 C22 80 22 88 28 92"), metal, 6), line(P("M70 76 C78 80 78 88 72 92"), metal, 6),
        fill(rect(27, 22, 46, 40, 14), c(0xE6EBF2)),
        fill(rect(33, 30, 34, 24, 9), c(0x1B2433)),
        line(P("M50 22 L50 12"), leg, 2),
        fill(circle(50, 10, 3.4), c(0xFF5D73), .antenna),
        fill(rect(39, 38, 6, 7, 2), glow, .eyes), fill(rect(55, 38, 6, 7, 2), glow, .eyes),
        line(P("M45 49 L55 49"), glow, 1.8, .mouthClosed),
        fill(rect(45, 47, 10, 4, 2), glow, .mouthOpen),
    ]
}()

private let cat: [Layer] = {
    let fur = c(0xF0A35A)
    return [
        line(P("M70 100 C88 100 92 84 86 74"), c(0xE8954A), 6, .tail),
        fill(ellipse(50, 92, 26, 16), fur),
        fill(ellipse(50, 96, 14, 9), c(0xFBE2C6)),
        fill(ellipse(38, 106, 7, 4), fur), fill(ellipse(62, 106, 7, 4), fur),
        fill(circle(50, 58, 20), fur),
        fill(P("M33 48 L32 30 L45 41 Z M67 48 L68 30 L55 41 Z"), fur),
        fill(P("M35 45 L35 35 L42 41 Z M65 45 L65 35 L58 41 Z"), c(0xF7C4B8)),
    ] + eyes(y: 58, dx: 8, r: 3) + [
        fill(P("M48 64 L52 64 L50 66.5 Z"), c(0xC4596A)),
        line(P("M30 64 L40 65 M30 68 L40 67 M70 64 L60 65 M70 68 L60 67"), Color.white.opacity(0.8), 1),
    ] + mouth(y: 68, c(0x8A3B2E))
}()

private let boo: [Layer] = [
    fill(P("M50 18 C30 18 20 34 20 54 L20 92 C20 100 26 106 34 104 C40 102 44 106 50 106 C56 106 60 102 66 104 C74 106 80 100 80 92 L80 54 C80 34 70 18 50 18 Z"), .white),
    line(P("M78 96 C90 96 92 84 86 80"), .white, 7, .tail),
] + eyes(y: 52, dx: 11, r: 4) + [
    fill(ellipse(34, 62, 4, 2), c(0xFFB3C1).opacity(0.7)),
    fill(ellipse(66, 62, 4, 2), c(0xFFB3C1).opacity(0.7)),
] + mouth(y: 64, c(0x2B2140))

/// A mascot, animated: blinking, leg swing / tail swish / antenna blink, gentle bob, and a moving
/// mouth while `talking`.
struct MascotCharacter: View {
    var kind: MascotKind
    var talking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layers: [Layer] {
        switch kind {
        case .kunoichi: kunoichi
        case .robot: robot
        case .cat: cat
        case .boo: boo
        }
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.scaleBy(x: size.width / 100, y: size.height / 110)
                ctx.translateBy(x: 0, y: CGFloat(sin(t * 2 * .pi / 4)) * -0.6 - (talking ? CGFloat(abs(sin(t * 6))) * 1.5 : 0))
                let blink = t.truncatingRemainder(dividingBy: 5.5) > 5.35
                let mouthOpen = talking && Int(t * 6) % 2 == 0
                for l in layers {
                    var g = ctx
                    let box = l.path.boundingRect
                    switch l.part {
                    case .legSwing:
                        rotate(&g, around: CGPoint(x: box.minX, y: box.midY), degrees: 7 * sin(t * 2 * .pi / 2.6))
                    case .tail:
                        rotate(&g, around: CGPoint(x: box.minX, y: box.maxY), degrees: -12 * sin(t * 2 * .pi / 2.2))
                    case .eyes where blink:
                        g.translateBy(x: 0, y: box.midY); g.scaleBy(x: 1, y: 0.1); g.translateBy(x: 0, y: -box.midY)
                    case .antenna where Int(t / 0.8) % 2 == 1:
                        g.opacity = 0.25
                    case .mouthClosed where mouthOpen, .mouthOpen where !mouthOpen:
                        continue
                    default: break
                    }
                    if let f = l.fill { g.fill(l.path, with: .color(f)) }
                    if let (color, w) = l.stroke { g.stroke(l.path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)) }
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
        .accessibilityLabel(kind.name)
    }

    private func rotate(_ g: inout GraphicsContext, around p: CGPoint, degrees: Double) {
        g.translateBy(x: p.x, y: p.y)
        g.rotate(by: .degrees(degrees))
        g.translateBy(x: -p.x, y: -p.y)
    }
}
