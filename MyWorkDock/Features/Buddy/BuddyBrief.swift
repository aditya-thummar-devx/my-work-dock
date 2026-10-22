import Foundation

/// The words that go with a custom buddy: the steps Settings shows, and the brief to paste into Claude Design. Both say what
/// `BuddyFileCheck` enforces; the numbers come from its `Limits`.
enum BuddyBrief {
    typealias Limits = BuddyFileCheck.Limits

    static let steps = [
        "Design it tiny: 36 × 28 px (28 × 28 works too), transparent, looping, \(Int(Limits.seconds)) s at most. The first frame is the resting pose: Still and Reduce Motion show it.",
        "Draw with circles, rounded rectangles, simple paths and emoji. Move, scale, rotate and fade them. No text, blur, shadows or effects.",
        "Name every shape that should follow your tint “tint”. Other colours stay as drawn, so pick ones that read on black and on light grey.",
        "Turn it into a Lottie .json: ask Claude Code to bake your Claude Design export, or export from a Lottie editor with the images embedded.",
        "Press + and pick the file. It is checked and copied here, so the original can move. If it is turned down, the reasons show under the buddies.",
    ]

    /// For Claude Design: what to make so that it can become a buddy.
    static let text = """
    Design a notch buddy: a tiny looping animation that sits beside the notch in a Mac menu bar.

    Canvas: 36 × 28 px (28 × 28 also works), transparent background, nothing outside it. It is shown at 36 × 28 pt, so keep the shapes bold and simple.
    Loop: seamless and endless, \(Int(Limits.seconds)) seconds at most. The first frame is the resting pose, shown when motion is off, so make it a good still.
    Draw only with circles, ellipses, rectangles, rounded rectangles, simple paths and emoji, with solid fills and strokes. No text, gradients, blur, shadows, filters or video.
    Animate only position (translate), scale, rotation and opacity, with CSS @keyframes and an infinite animation, using ease or ease-in-out timing.
    Colour: give the shapes that should take the user's accent colour the class "tint". Every other colour stays as drawn. The buddy sits on black in the dark theme and on light grey in the light theme, so pick colours that read on both.
    Deliver one HTML file holding the animation only: no scripts, no external files.
    """
}
