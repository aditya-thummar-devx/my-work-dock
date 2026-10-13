import SwiftUI

/// Parses SVG path data (`d` attribute) into a SwiftUI `Path`, in the SVG's own coordinate space.
/// Supports M L H V C A Z in absolute and relative form, including implicit command repetition.
/// Used to draw the designs' icons exactly (DESIGN_SPEC §3 allows SF Symbols, but exact parity needs the SVGs).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var tokens: [Token] = []
        var scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t")
        let commands = CharacterSet(charactersIn: "MmLlHhVvCcAaZz")
        while !scanner.isAtEnd {
            if let c = scanner.scanCharacters(from: commands) {
                // Commands are single letters; `scanCharacters` may glue "z" + "M", so split.
                c.forEach { tokens.append(.command($0)) }
            } else if let v = scanner.scanDouble() {
                tokens.append(.number(CGFloat(v)))
            } else {
                _ = scanner.scanCharacter()
            }
        }

        var path = Path()
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var cmd: Character = "M"
        var i = 0

        func next() -> CGFloat {
            defer { i += 1 }
            if i < tokens.count, case .number(let v) = tokens[i] { return v }
            return 0
        }
        func pt(_ rel: Bool) -> CGPoint {
            let x = next(), y = next()
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        while i < tokens.count {
            if case .command(let c) = tokens[i] {
                cmd = c
                i += 1
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    cur = start
                    continue
                }
            } else if cmd == "Z" || cmd == "z" {
                i += 1 // stray number after close
                continue
            }
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                cur = pt(rel)
                start = cur
                path.move(to: cur)
                cmd = rel ? "l" : "L" // further pairs are implicit lineto
            case "L", "l":
                cur = pt(rel)
                path.addLine(to: cur)
            case "H", "h":
                let x = next()
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
            case "V", "v":
                let y = next()
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
            case "C", "c":
                let c1 = pt(rel), c2 = pt(rel)
                let end = pt(rel)
                path.addCurve(to: end, control1: c1, control2: c2)
                cur = end
            case "A", "a":
                let rx = next(), ry = next(), rot = next(), large = next(), sweep = next()
                let end = pt(rel)
                addArc(&path, from: cur, rx: rx, ry: ry, rotation: rot, large: large != 0, sweep: sweep != 0, to: end)
                cur = end
            default:
                i += 1
            }
        }
        return path
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    /// SVG endpoint arc → cubic Béziers (SVG 1.1 implementation notes, F.6.5).
    private static func addArc(_ path: inout Path, from p0: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool, to p1: CGPoint) {
        guard p0 != p1 else { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }
        let sign: CGFloat = large == sweep ? -1 : 1
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = sign * max(0, numerator / denominator).squareRoot()
        let cxp = coef * (rx * y1 / ry)
        let cyp = coef * -(ry * x1 / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let t = 4 / 3 * tan(step / 4)
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cosPhi * rx * x - sinPhi * ry * y + cx, y: sinPhi * rx * x + cosPhi * ry * y + cy)
        }
        var theta = theta1
        for _ in 0..<segments {
            let c1 = cos(theta), s1 = sin(theta), c2 = cos(theta + step), s2 = sin(theta + step)
            path.addCurve(to: map(c2, s2),
                          control1: map(c1 - t * s1, s1 + t * c1),
                          control2: map(c2 + t * s2, s2 - t * c2))
            theta += step
        }
    }
}
