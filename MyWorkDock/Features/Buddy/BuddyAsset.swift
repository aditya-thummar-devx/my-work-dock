import Lottie
import SwiftUI

/// One buddy animation: a Lottie file in Resources/Buddies, baked by scripts/bake-buddies.py at the Lively pace, or one the user added
/// (`CustomBuddyStore`). Calm plays the same file slower. The layers that take the user's tint are named `tint`; the rest keeps its own colours.
struct BuddyAsset: Equatable {
    /// The bundled file's name; for a custom buddy only a name to tell it from the others.
    var file: String
    /// Calm's playback speed: the Lively loops over Calm's (blink 4 s to 9 s, ring 2 s to 4 s, wave 2.4 s to 6 s).
    var calmSpeed: Double
    /// Points the composition has around the box its content takes up; the hint's wave swings out of that box.
    var margin: CGFloat = 0
    /// The library file of a custom buddy (already through `BuddyFileCheck`).
    var url: URL?

    /// The first-launch hint's 👋: it waves three times and rests.
    static let hello = BuddyAsset(file: "buddy-hello", calmSpeed: 1, margin: Geo.Buddy.Hint.waveMargin)

    /// A buddy from the library. Calm plays it at 0.45, about the pace the bundled ones slow to.
    static func custom(_ entry: CustomBuddyStore.Entry) -> BuddyAsset { BuddyAsset(file: "custom \(entry.id)", calmSpeed: 0.45, url: entry.url) }

    func speed(for motion: BuddyMotion) -> Double { motion == .calm ? calmSpeed : 1 }

    /// The parsed file; Lottie keeps it by name or path, so asking again is cheap.
    var animation: LottieAnimation? { url.map { LottieAnimation.filepath($0.path) } ?? LottieAnimation.named(file, bundle: .main) }

    /// What to draw at: the bundled files are composed to the slot, a custom one is fitted into it.
    var size: CGSize {
        guard let natural = animation?.size, url != nil, natural.width > 0, natural.height > 0 else { return animation?.size ?? .zero }
        let k = min(Geo.Buddy.ear / natural.width, Geo.Buddy.height / natural.height)
        return CGSize(width: natural.width * k, height: natural.height * k)
    }
}

extension BuddyAsset {
    init(_ style: BuddyStyle, emoji: BuddyEmoji) {
        switch style {
        case .face, .custom: self.init(file: "buddy-face", calmSpeed: 4.0 / 9) // a custom buddy has its own init, below
        case .pulse: self.init(file: "buddy-pulse", calmSpeed: 2.0 / 4)
        case .emoji: self.init(file: "buddy-emoji-\(emoji.rawValue)", calmSpeed: 2.4 / 6)
        }
    }

    /// What the prefs ask to see. A custom buddy that is no longer in the library shows the face.
    @MainActor
    init(_ prefs: BuddyPrefs, library: CustomBuddyStore) {
        if prefs.style == .custom, let entry = library.entry(prefs.custom) {
            self = .custom(entry)
        } else {
            self.init(prefs.style, emoji: prefs.emoji)
        }
    }
}
