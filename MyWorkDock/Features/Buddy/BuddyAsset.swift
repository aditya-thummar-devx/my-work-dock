import Lottie
import SwiftUI

/// One buddy animation: a Lottie file in Resources/Buddies, baked by scripts/bake-buddies.py at the Lively pace. Calm plays the same
/// file slower. The layers that take the user's tint are named `tint`; the rest keeps its own colours.
struct BuddyAsset: Equatable {
    var file: String
    /// Calm's playback speed: the Lively loops over Calm's (blink 4 s to 9 s, ring 2 s to 4 s, wave 2.4 s to 6 s).
    var calmSpeed: Double
    /// Points the composition has around the box its content takes up; the hint's wave swings out of that box.
    var margin: CGFloat = 0

    /// The first-launch hint's 👋: it waves three times and rests.
    static let hello = BuddyAsset(file: "buddy-hello", calmSpeed: 1, margin: Geo.Buddy.Hint.waveMargin)

    func speed(for motion: BuddyMotion) -> Double { motion == .calm ? calmSpeed : 1 }

    /// The parsed file; Lottie keeps it by name, so asking again is cheap.
    var animation: LottieAnimation? { LottieAnimation.named(file, bundle: .main) }
    var size: CGSize { animation?.size ?? .zero }
}

extension BuddyAsset {
    init(_ style: BuddyStyle, emoji: BuddyEmoji) {
        switch style {
        case .face: self.init(file: "buddy-face", calmSpeed: 4.0 / 9)
        case .pulse: self.init(file: "buddy-pulse", calmSpeed: 2.0 / 4)
        case .emoji: self.init(file: "buddy-emoji-\(emoji.rawValue)", calmSpeed: 2.4 / 6)
        }
    }
}
