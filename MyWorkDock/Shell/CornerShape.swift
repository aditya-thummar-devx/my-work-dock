import SwiftUI

/// The quarter-circle fan silhouette shown when the user hovers over a corner-mode shell.
/// The arc fills from the corner outward: `innerRadius` is the hollow centre, `thickness`
/// is how deep the filled band is, and `anchor` says which corner the shape grows from.
///
/// All four coordinates are in the view's own local coordinate space where (0, 0) is the
/// corner the arc fans from. The bounding box the view is drawn in must be a square whose
/// side equals `innerRadius + thickness`.
struct CornerHoverShape: Shape {
    /// Distance from the corner to the inner edge of the arc band.
    var innerRadius: CGFloat
    /// Radial depth of the filled band (outer radius = innerRadius + thickness).
    var thickness: CGFloat
    /// Which corner to root the fan at.
    var anchor: CornerAnchor

    // MARK: Animatable

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(innerRadius, thickness) }
        set { (innerRadius, thickness) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let outer = innerRadius + thickness
        // Start/end angles depend on the corner. The arc sweeps a 90° quarter of a circle.
        // SwiftUI angles: 0° = right (3 o'clock), 90° = down, 180° = left, 270° = up.
        // Corner origin in local space is always (0,0); the rect origin matches the corner.
        let (startAngle, endAngle, centre): (Angle, Angle, CGPoint)
        switch anchor {
        case .bottomLeft:
            // Corner is bottom-left; arc fans up and to the right (270° → 360°/0°)
            startAngle = .degrees(270)
            endAngle   = .degrees(360)
            centre = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            // Corner is bottom-right; arc fans up and to the left (180° → 270°)
            startAngle = .degrees(180)
            endAngle   = .degrees(270)
            centre = CGPoint(x: rect.maxX, y: rect.maxY)
        }

        var p = Path()
        // Outer arc
        p.addArc(center: centre, radius: outer, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        // Line to inner arc end
        let innerEnd = CGPoint(
            x: centre.x + innerRadius * cos(endAngle.radians),
            y: centre.y + innerRadius * sin(endAngle.radians)
        )
        p.addLine(to: innerEnd)
        // Inner arc (reverse direction to close the band)
        p.addArc(center: centre, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// The tiny rounded-square shape shown at idle in corner mode.
/// Identical to `RoundedRectangle` but conforms to `Shape` explicitly so callers
/// can use the same type regardless of mode.
struct CornerIdleShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
    }
}
