import SwiftUI

/// The notch silhouette: flat top edge, concave shoulders flaring outward at the top corners,
/// straight sides, convex bottom corners. Drawn in the rect of the *body*; the shoulders extend
/// `shoulder` points beyond the rect on each side (DESIGN_SPEC §1), so callers must not clip to the rect.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat = Geo.shoulder

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bottomRadius, shoulder) }
        set { (bottomRadius, shoulder) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let s = shoulder
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)

        var p = Path()
        p.move(to: CGPoint(x: x0 - s, y: y0))
        p.addLine(to: CGPoint(x: x1 + s, y: y0))
        // Concave shoulder: circle of radius s centred at (x1 + s, y0 + s).
        p.addArc(tangent1End: CGPoint(x: x1, y: y0), tangent2End: CGPoint(x: x1, y: y0 + s), radius: s)
        p.addLine(to: CGPoint(x: x1, y: y1 - r))
        p.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x1 - r, y: y1), radius: r)
        p.addLine(to: CGPoint(x: x0 + r, y: y1))
        p.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y1 - r), radius: r)
        p.addLine(to: CGPoint(x: x0, y: y0 + s))
        p.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x0 - s, y: y0), radius: s)
        p.closeSubpath()
        return p
    }
}
