import AppKit

/// What the screen is doing that the notch buddy cares about, fed to the model:
///  - which displays have no menu bar showing, because a full-screen app is in front there or the menu bar is set to hide. The ear
///    sits in the menu bar's strip, so there it would float over the app (Settings › Notch buddy › Hide in full-screen apps). Read
///    from the Window Server's menu-bar windows, one per display on layer 24: owner, layer and bounds need no permission;
///  - whether the screen is awake. A sleeping display or a switched-out session shows nothing, so nothing should wake the app to
///    animate a face no one can see.
@MainActor
final class ScreenWatcher {
    private let model: NotchModel
    private var settle: DispatchWorkItem?

    init(model: NotchModel) {
        self.model = model
        // Entering or leaving full screen is a Space change; the app in front can change without one.
        let workspace = NSWorkspace.shared.notificationCenter
        watch(workspace, [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                          NSWorkspace.screensDidWakeNotification]) { $0.changed() }
        watch(workspace, [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]) { $0.model.setScreenAwake(false) }
        watch(workspace, [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]) { $0.model.setScreenAwake(true) }
        watch(.default, [NSApplication.didChangeScreenParametersNotification]) { $0.changed() }
    }

    /// Lives as long as the app: the observers are never removed.
    private func watch(_ center: NotificationCenter, _ names: [Notification.Name], _ work: @escaping @MainActor (ScreenWatcher) -> Void) {
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { work(self) } }
            }
        }
    }

    /// Reads now, and again once the Space animation (a little under a second) has settled.
    func changed() {
        refresh()
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Nothing is read while the buddy is off or may show in full screen: no one is waiting for the answer.
    func refresh() {
        guard model.buddy.on, model.buddy.hideInFullScreen else { return model.setMenuBarHidden([]) }
        model.setMenuBarHidden(Self.displaysWithoutMenuBar())
    }

    /// Displays whose top strip shows no menu bar right now.
    static func displaysWithoutMenuBar() -> Set<DisplayID> {
        guard let main = NSScreen.screens.first else { return [] }
        // Each display's top strip in the Window Server's coordinates (origin top left of the main display).
        var strips: [DisplayID: CGRect] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID {
                strips[id] = CGRect(x: screen.frame.minX, y: main.frame.maxY - screen.frame.maxY, width: screen.frame.width, height: 40)
            }
        }
        let shown = menuBars(windows(.optionOnScreenOnly))
        // No bar on screen at all is an answer only if this macOS keeps its menu bars as windows (off screen, then): otherwise it is
        // not how this one draws them, and the buddy never hides on a guess.
        if shown.isEmpty, menuBars(windows(.optionAll)).isEmpty { return [] }
        return displaysWithoutBar(shown, strips: strips)
    }

    private static func windows(_ option: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    /// The menu-bar windows of a Window Server list (owner "Window Server", layer 24, a strip rather than a screen), in its coordinates.
    static func menuBars(_ windows: [[String: Any]]) -> [CGRect] {
        windows.compactMap { w in
            guard w[kCGWindowOwnerName as String] as? String == "Window Server", w[kCGWindowLayer as String] as? Int == 24,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return r.height < 100 ? r : nil
        }
    }

    /// The displays none of `bars` covers the top strip of. A bar sliding in or out during a Space change still overlaps its strip,
    /// so only a display with no bar near it is without.
    static func displaysWithoutBar(_ bars: [CGRect], strips: [DisplayID: CGRect]) -> Set<DisplayID> {
        Set(strips.filter { _, strip in
            !bars.contains { let hit = $0.intersection(strip); return hit.height >= 10 && hit.width >= 100 }
        }.keys)
    }
}
