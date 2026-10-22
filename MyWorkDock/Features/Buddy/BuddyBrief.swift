import Foundation

/// The words that go with a custom buddy: the steps Settings shows, and the brief to paste into Claude Design. Both say what
/// `BuddyFileCheck` enforces; the numbers come from its `Limits`.
enum BuddyBrief {
    typealias Limits = BuddyFileCheck.Limits

    static let steps = [
        "Design it at notch scale: 1 px is 1 pt, the ear is 36 × 28, up to 120 × 120 if it hangs out. Transparent, \(Int(Limits.seconds)) s at most. The idle file's first frame is the resting pose: Still and Reduce Motion show it.",
        "Up to three files: Idle (loops), Every ~45 s (plays once, then back to idle) and After 10 min (loops until you hover). Only Idle is needed. Each one can sit at its own offset from the ear.",
        "Draw with circles, rounded rectangles, simple paths and emoji. Move, scale, rotate and fade them. No text, blur, shadows or effects. Name every shape that should follow your tint “tint”.",
        "Turn each into a Lottie .json: ask Claude Code to bake your Claude Design export, or export from a Lottie editor with the images embedded.",
        "Press + and pick the idle file, then add the others and set the offsets below the buddies. Every file is checked and copied here. If one is turned down, the reasons show under the buddies.",
    ]

    /// For Claude Design: what to make so that it can become a buddy.
    static let text = """
    Design a notch buddy: a tiny character that lives beside the notch in a Mac menu bar, in up to three animations.

    1. Idle: loops all the time. Its first frame is the resting pose, shown when motion is off, so make it a good still.
    2. Every ~45 s: plays once, then the buddy goes back to Idle. Start and end on the idle pose so the swap is smooth.
    3. After 10 min without a hover: loops until the user hovers (napping, say).

    Scale: 1 px is 1 pt on screen. The ear beside the notch is 36 × 28 px; a state may be bigger (up to 120 × 120 px) and be moved out of the ear, for instance hanging below the notch. Keep the shapes bold and simple.
    Each animation: transparent background, nothing outside its canvas, seamless, \(Int(Limits.seconds)) seconds at most.
    Draw only with circles, ellipses, rectangles, rounded rectangles, simple paths and emoji, with solid fills and strokes. No text, gradients, blur, shadows, filters or video.
    Animate only position (translate), scale, rotation and opacity, with CSS @keyframes, using ease or ease-in-out timing.
    Colour: give the shapes that should take the user's accent colour the class "tint". Every other colour stays as drawn. In the ear the buddy sits on black (dark theme) or light grey (light theme); outside it, on the menu bar or the app below. Pick colours that read on all of them.
    Deliver one HTML file per animation, holding the animation only: no scripts, no external files. Say where each should sit relative to the ear's centre, in points.
    """
}
