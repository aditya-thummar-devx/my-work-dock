import AppKit
import Observation

/// Whether macOS is in dark mode right now, kept live: `ThemeMode.system` follows it without a restart.
/// Watches `NSApp.effectiveAppearance` (the app sets no appearance of its own, so it is the system's).
@MainActor @Observable
final class AppearanceObserver {
    private(set) var isDark: Bool
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Fixed value, nothing observed: what the snapshots and tests use.
    init(isDark: Bool) { self.isDark = isDark }

    /// The running app.
    static func live() -> AppearanceObserver {
        let observer = AppearanceObserver(isDark: Self.systemIsDark)
        observer.observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak observer] _, _ in
            Task { @MainActor in observer?.isDark = AppearanceObserver.systemIsDark }
        }
        return observer
    }

    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Snapshot states only.
    func set(isDark: Bool) { self.isDark = isDark }
}
