import Foundation

/// Settings › Appearance › Notch buddy (v3 change 8). The raw values are stored in UserDefaults.
enum BuddyStyle: String, CaseIterable, Identifiable {
    case face, pulse, emoji, custom

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum BuddyMotion: String, CaseIterable, Identifiable {
    case lively, calm, still

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum BuddyEmoji: String, CaseIterable, Identifiable {
    case wave, sparkle, robot, cat, eyes

    var id: String { rawValue }
    var glyph: String {
        switch self {
        case .wave: "👋"
        case .sparkle: "✨"
        case .robot: "🤖"
        case .cat: "🐱"
        case .eyes: "👀"
        }
    }
    /// What VoiceOver says for the tile.
    var name: String {
        switch self {
        case .wave: "Waving hand"
        case .sparkle: "Sparkles"
        case .robot: "Robot"
        case .cat: "Cat"
        case .eyes: "Eyes"
        }
    }
}

/// Everything Settings › Appearance › Notch buddy can change. The defaults are the designed ones.
struct BuddyPrefs: Equatable {
    var on = true
    var style = BuddyStyle.face
    var emoji = BuddyEmoji.wave
    /// The library entry (`CustomBuddyStore.Entry.id`) the Custom style shows.
    var custom: String?
    var motion = BuddyMotion.lively
    var hideInFullScreen = true
}

extension BuddyPrefs {
    private enum Key {
        static let on = "buddyOn"
        static let style = "buddyStyle"
        static let emoji = "buddyEmoji"
        static let custom = "buddyCustom"
        static let motion = "buddyMotion"
        static let hideInFullScreen = "buddyHideInFullScreen"
    }

    /// What was saved; anything missing or unreadable is the designed default.
    init(defaults: UserDefaults) {
        on = defaults.object(forKey: Key.on) as? Bool ?? on
        style = defaults.string(forKey: Key.style).flatMap(BuddyStyle.init(rawValue:)) ?? style
        emoji = defaults.string(forKey: Key.emoji).flatMap(BuddyEmoji.init(rawValue:)) ?? emoji
        custom = defaults.string(forKey: Key.custom)
        motion = defaults.string(forKey: Key.motion).flatMap(BuddyMotion.init(rawValue:)) ?? motion
        hideInFullScreen = defaults.object(forKey: Key.hideInFullScreen) as? Bool ?? hideInFullScreen
    }

    func save(to defaults: UserDefaults) {
        defaults.set(on, forKey: Key.on)
        defaults.set(style.rawValue, forKey: Key.style)
        defaults.set(emoji.rawValue, forKey: Key.emoji)
        defaults.set(custom, forKey: Key.custom) // nil removes it
        defaults.set(motion.rawValue, forKey: Key.motion)
        defaults.set(hideInFullScreen, forKey: Key.hideInFullScreen)
    }
}

/// What a custom buddy plays when. The built-in buddies only have the idle loop.
enum BuddyState: String, CaseIterable, Identifiable, Codable {
    /// Loops whenever the notch is idle.
    case idle
    /// Plays once every ~45 s, then back to idle.
    case glance
    /// After 10 min without a hover or an open panel; a hover wakes it.
    case nap

    var id: String { rawValue }
    var label: String {
        switch self {
        case .idle: "Idle"
        case .glance: "Every ~45 s"
        case .nap: "After 10 min"
        }
    }
    var caption: String {
        switch self {
        case .idle: "Loops while the notch is idle."
        case .glance: "Plays once, then back to idle."
        case .nap: "Loops after 10 minutes without a hover."
        }
    }
    /// Its file in the buddy's folder.
    var fileName: String { "\(rawValue).json" }
}

/// Where each state of a custom buddy sits: points from the centre of the ear, x to the right, y down. Kept in the buddy's folder.
struct BuddyOffsets: Codable, Equatable {
    var idle = CGPoint.zero
    var glance = CGPoint.zero
    var nap = CGPoint.zero

    subscript(state: BuddyState) -> CGPoint {
        get {
            switch state {
            case .idle: idle
            case .glance: glance
            case .nap: nap
            }
        }
        set {
            let p = Self.clamped(newValue)
            switch state {
            case .idle: idle = p
            case .glance: glance = p
            case .nap: nap = p
            }
        }
    }

    /// Whole points inside `Geo.Buddy.States.offsetX` / `offsetY`.
    static func clamped(_ p: CGPoint) -> CGPoint {
        let x = Geo.Buddy.States.offsetX, y = Geo.Buddy.States.offsetY
        return CGPoint(x: min(max(p.x.rounded(), x.lowerBound), x.upperBound), y: min(max(p.y.rounded(), y.lowerBound), y.upperBound))
    }
}
