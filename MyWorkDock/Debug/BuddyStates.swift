#if DEBUG
import SwiftUI

/// Snapshot states for the notch buddy (`MyWorkDock --snapshot buddy-idle --out x.png`). The designs' boards are screenshots/v3
/// b01-b06 (Buddy-States, Buddy-Settings); these draw the same states with the real shell and Settings. The idle ones use the
/// notch strip canvas; the settings ones show just the block, as the Appearance page scrolls it into view.
enum BuddyStates {
    /// The strip under the notch: the first-launch hint hangs ~50 pt below it.
    private static func idle(_ name: String, theme: ThemeMode = .dark, tint: Tint = .lime, hint: Bool = false, _ prefs: BuddyPrefs = BuddyPrefs()) -> SnapshotRunner.State {
        SnapshotRunner.State(name, .notch) {
            $0.setTheme(theme)
            $0.setTint(tint)
            $0.setBuddy(prefs)
            if hint { $0.resetBuddyHint() }
        }
    }

    /// Where Appearance puts the block: the content column of the settings screen (nav 170 + divider + gap), a little below the fold.
    /// 8 pt wider on the left, so the fragment also covers the real page's tint swatches, which stick out beside the column.
    private static let settingsBlock = CGRect(x: Geo.Chrome.insetX + Geo.Settings.navWidth + 1 + Geo.Settings.contentGapLeft - 8,
                                              y: Geo.Chrome.topRowHeight + Geo.Chrome.subNavTop, width: Geo.Settings.contentMaxWidth + 8, height: 420)

    private static func settings(_ name: String, theme: ThemeMode = .dark, tint: Tint = .lime, _ prefs: BuddyPrefs) -> SnapshotRunner.State {
        .fragment(name, theme: theme, tint: tint, settings: true, rect: settingsBlock) {
            BuddySettings(prefs: prefs).padding(.leading, 8).onPanel()
        }
    }

    /// The Custom block is taller than the others (the buddies, the limits, five steps and the brief button): the artboard canvas has room.
    /// Bundled files stand in for the user's, named as a user might.
    private static func customSettings(_ name: String, theme: ThemeMode = .dark, tint: Tint = .lime, prefs: BuddyPrefs, library: [String] = ["Cat", "Round", "Spark"],
                                       rejection: [String] = []) -> SnapshotRunner.State {
        let files = ["Cat": "buddy-emoji-cat", "Round": "buddy-face", "Spark": "buddy-emoji-sparkle"]
        let rect = CGRect(x: settingsBlock.minX, y: settingsBlock.minY, width: settingsBlock.width, height: 560)
        return .fragment(name, .artboard, theme: theme, tint: tint, settings: true, rect: rect) {
            MainActor.assumeIsolated {
                let entries = library.compactMap { id in files[id].flatMap { Bundle.main.url(forResource: $0, withExtension: "json") }.map { CustomBuddyStore.Entry(id: id, url: $0) } }
                return BuddySettings(prefs: prefs, customs: CustomBuddies(library: .sample(entries, rejection: rejection))).padding(.leading, 8).onPanel()
            }
        }
    }

    static let all: [SnapshotRunner.State] = [
        idle("buddy-first-launch", hint: true),
        idle("buddy-idle"),
        idle("buddy-pulse", BuddyPrefs(style: .pulse)),
        idle("buddy-emoji-cat", BuddyPrefs(style: .emoji, emoji: .cat)),
        idle("buddy-off", BuddyPrefs(on: false)),
        idle("buddy-idle-light", theme: .light),
        idle("buddy-idle-light-teal", theme: .light, tint: .teal),
        idle("buddy-pulse-light", theme: .light, BuddyPrefs(style: .pulse)),
        idle("buddy-idle-blue", tint: .blue),
        settings("buddy-settings-face", BuddyPrefs()),
        settings("buddy-settings-pulse", BuddyPrefs(style: .pulse)),
        settings("buddy-settings-emoji-cat", BuddyPrefs(style: .emoji, emoji: .cat)),
        settings("buddy-settings-calm", BuddyPrefs(style: .emoji, emoji: .cat, motion: .calm)),
        settings("buddy-settings-off", BuddyPrefs(on: false, style: .emoji, emoji: .cat, motion: .calm)),
        settings("buddy-settings-light", theme: .light, BuddyPrefs(style: .emoji, emoji: .cat)),
        customSettings("buddy-settings-custom", prefs: BuddyPrefs(style: .custom, custom: "Round")),
        customSettings("buddy-settings-custom-light", theme: .light, tint: .teal, prefs: BuddyPrefs(style: .custom, custom: "Spark")),
        customSettings("buddy-settings-custom-empty", prefs: BuddyPrefs(style: .custom), library: []),
        customSettings("buddy-settings-custom-rejected", prefs: BuddyPrefs(style: .custom, custom: "Cat"),
                       rejection: ["Over 256 KB (this file is 410 KB).", "It runs 41.0 s; the limit is 30 s.", "It uses text layers; the buddy cannot show that.",
                                   "It has 31 layers; the limit is 30."]),
    ]
}
#endif
