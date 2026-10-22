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

    /// One state of a buddy from the library (its idle file when it has none for `state`). Calm plays it at 0.45, about the pace the
    /// bundled ones slow to.
    static func custom(_ entry: CustomBuddyStore.Entry, _ state: BuddyState = .idle) -> BuddyAsset {
        let url = entry.files[state] ?? entry.url
        return BuddyAsset(file: "custom \(entry.id) \(url.lastPathComponent)", calmSpeed: 0.45, url: url)
    }

    func speed(for motion: BuddyMotion) -> Double { motion == .calm ? calmSpeed : 1 }

    /// The parsed file; Lottie keeps it by name or path, so asking again is cheap.
    var animation: LottieAnimation? { url.map { LottieAnimation.filepath($0.path) } ?? LottieAnimation.named(file, bundle: .main) }

    /// What to draw at: the bundled files are composed to the slot; a custom one at its own size (1 unit = 1 pt), so it can hang out
    /// of the ear, shrunk only to fit `Geo.Buddy.States.maxSize`.
    var size: CGSize {
        guard let natural = animation?.size, url != nil, natural.width > 0, natural.height > 0 else { return animation?.size ?? .zero }
        let max = Geo.Buddy.States.maxSize
        let k = min(1, max.width / natural.width, max.height / natural.height)
        return CGSize(width: natural.width * k, height: natural.height * k)
    }

    /// One play-through at `speed`, in seconds.
    func duration(speed: Double) -> Double { (animation?.duration ?? 0) / max(speed, 0.01) }
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

/// What the buddy can play: the idle loop, and for a custom buddy its glance and nap when it has them, each at its own offset.
struct BuddySet: Equatable {
    var assets: [BuddyState: BuddyAsset]
    var offsets = BuddyOffsets()

    var idle: BuddyAsset { assets[.idle]! }

    /// The built-in buddies: idle only, where they always sat.
    init(_ idle: BuddyAsset) { assets = [.idle: idle] }

    init(_ entry: CustomBuddyStore.Entry) {
        assets = Dictionary(uniqueKeysWithValues: entry.files.keys.map { ($0, BuddyAsset.custom(entry, $0)) })
        offsets = entry.offsets
    }

    /// What the prefs ask to see. A custom buddy that is no longer in the library shows the face.
    @MainActor
    init(_ prefs: BuddyPrefs, library: CustomBuddyStore) {
        if prefs.style == .custom, let entry = library.entry(prefs.custom) {
            self.init(entry)
        } else {
            self.init(BuddyAsset(prefs.style, emoji: prefs.emoji))
        }
    }
}
