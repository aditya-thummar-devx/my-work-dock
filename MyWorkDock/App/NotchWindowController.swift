import AppKit
import SwiftUI

/// Owns the panels: one per display with the shell (one on the notch display, or one per display when
/// `showOnAllDisplays`), feeds pointer position to the model, and keeps `ignoresMouseEvents` so clicks
/// outside the drawn shape fall through to apps underneath.
@MainActor
final class NotchWindowController {
    /// Room around the open shell for its shoulders and `0 24 70` shadow.
    private static let panelMargin = CGSize(width: 200, height: 120)
    /// The window always fits the large panel, so a size change never resizes it mid-animation; clicks outside the shell fall through.
    private static func panelSize(on screen: CGSize) -> CGSize {
        let open = PanelSize.large.size(on: screen)
        return CGSize(width: open.width + panelMargin.width, height: open.height + panelMargin.height)
    }
    /// The cursor can sit exactly on the screen's top edge; extend hit rects upward so it still counts.
    private static let topSlop: CGFloat = 2

    /// One display's panel and where its shell sits in global screen coordinates.
    @MainActor
    private final class Shell {
        let id: DisplayID
        let panel: NotchPanel
        let screen: ShellScreen
        var centerX: CGFloat = 0
        var topY: CGFloat = 0
        var frame: CGRect = .zero

        init(id: DisplayID, model: NotchModel) {
            self.id = id
            let screen = ShellScreen()
            screen.id = id
            self.screen = screen
            panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1)) // `place` sizes it
            let host = FirstMouseHostingView(rootView: NotchRoot(model: model, screen: screen))
            host.sizingOptions = []
            panel.contentView = host
            panel.onEscape = { [weak model] in model?.closePanel() }
        }

        /// `NSRect.contains` is half-open, and the pointer sits exactly on `maxY` at the top edge.
        func owns(_ p: NSPoint) -> Bool { p.x >= frame.minX && p.x < frame.maxX && p.y >= frame.minY && p.y <= frame.maxY }
    }

    let model: NotchModel
    private var shells: [DisplayID: Shell] = [:]
    /// `model.showOnAllDisplays` as of the last `syncShells`.
    private var allShown = false
    private var monitors: [Any] = []

    init(model: NotchModel) {
        self.model = model

        syncShells()
        modelChanged()

        model.onChange = { [weak self] in self?.modelChanged() }
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { monitors.append(m) }
        // ⌘F opens search in the visible Clipboard or Notes tab; Tab cycles the main menu, Shift+Tab its sub-tabs (not while typing in a field).
        // The panel has no menu bar to carry either shortcut.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.activeShell?.panel, panel.isKeyWindow, self.model.mode == .open else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 48, flags.isEmpty || flags == .shift, !(panel.firstResponder is NSText) {
                    if flags.isEmpty { self.model.cycleMainTab() } else { self.model.cycleInnerTab() }
                    return nil
                }
                guard flags == .command, event.charactersIgnoringModifiers == "f" else { return event }
                self.model.openSearch()
                return nil
            }
        }) { monitors.append(m) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncShells() }
        }
    }

    // MARK: Placement

    /// The screen with a notch; with none, the screen the pointer is on (so an external display works), else the main one.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
    }

    private var activeShell: Shell? { model.activeDisplay.flatMap { shells[$0] } }

    /// Makes `shells` match the displays that should carry one, and places each.
    private func syncShells() {
        let follow = model.mode == .idle || model.mode == .live
        let screens: [NSScreen]
        if model.showOnAllDisplays {
            screens = NSScreen.screens
        } else if !follow, let id = shells.keys.first, let current = NSScreen.screens.first(where: { $0.displayID == id }) {
            screens = [current] // never move a panel that is open or hovered
        } else {
            screens = targetScreen.map { [$0] } ?? []
        }
        var keep: Set<DisplayID> = []
        for screen in screens {
            guard let id = screen.displayID else { continue }
            keep.insert(id)
            let isNew = shells[id] == nil
            let shell = shells[id] ?? addShell(id)
            place(shell, on: screen)
            if isNew { shell.panel.orderFrontRegardless() }
        }
        for id in shells.keys where !keep.contains(id) {
            shells.removeValue(forKey: id)?.panel.orderOut(nil)
        }
        allShown = model.showOnAllDisplays
        if !(model.activeDisplay.map(keep.contains) ?? false) {
            model.setActiveDisplay((shells.values.first { $0.screen.notch != nil } ?? shells.values.first)?.id)
        }
        updateMouse()
    }

    private func addShell(_ id: DisplayID) -> Shell {
        let shell = Shell(id: id, model: model)
        shells[id] = shell
        return shell
    }

    private static func hardwareNotch(of screen: NSScreen) -> (centerX: CGFloat, size: CGSize)? {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else { return nil }
        return ((l.maxX + r.minX) / 2, CGSize(width: r.minX - l.maxX, height: screen.safeAreaInsets.top))
    }

    private func place(_ shell: Shell, on screen: NSScreen) {
        let hardware = Self.hardwareNotch(of: screen)
        let cx = hardware?.centerX ?? screen.frame.midX
        let notch = hardware?.size
        if notch != shell.screen.notch {
            shell.screen.notch = notch
            if let notch {
                NSLog("MyWorkDock: hardware notch %.0f pt wide, %.0f pt tall, centre x %.1f", notch.width, notch.height, cx)
            } else {
                NSLog("MyWorkDock: no hardware notch on this screen")
            }
        }
        // No notch here: idle mirrors another display's notch; the pill only when no display has one.
        let borrowed = notch == nil ? NSScreen.screens.lazy.compactMap(Self.hardwareNotch).first?.size : nil
        if borrowed != shell.screen.borrowedNotch { shell.screen.borrowedNotch = borrowed }
        shell.centerX = cx
        shell.topY = screen.frame.maxY
        shell.frame = screen.frame
        shell.screen.size = screen.frame.size
        let size = Self.panelSize(on: screen.frame.size)
        let frame = NSRect(x: cx - size.width / 2, y: shell.topY - size.height, width: size.width, height: size.height)
        if shell.panel.frame != frame { shell.panel.setFrame(frame, display: true) }
    }

    // MARK: Pointer and key status

    /// Screen-space rect of the shell on `shell` for `g`.
    private func rect(_ g: ShellGeometry, _ shell: Shell) -> NSRect {
        NSRect(x: shell.centerX + g.centerOffset - g.width / 2, y: shell.topY - g.height,
               width: g.width, height: g.height + Self.topSlop)
    }

    private func geometry(_ shell: Shell) -> ShellGeometry { model.geometry(notch: shell.screen.idleNotch, on: shell.id, screen: shell.screen.size) }

    /// Each panel takes clicks only over its own drawn shape.
    private func updateMouse() {
        let p = NSEvent.mouseLocation
        for s in shells.values { s.panel.ignoresMouseEvents = !rect(geometry(s), s).contains(p) }
    }

    private func pointerMoved() {
        let p = NSEvent.mouseLocation
        // Until the pointer has entered a shell, the display it is on decides which one peeks and opens.
        if !model.hover, model.mode != .open, let s = shells.values.first(where: { $0.owns(p) }) { model.setActiveDisplay(s.id) }
        guard let s = activeShell else { return updateMouse() }
        var g = geometry(s)
        let stay = rect(g, s)
        // While only the live activity is showing, entering is limited to peek height, otherwise the
        // 48 → 70 pt height change makes the shell flicker between peek and live under a resting pointer.
        // ponytail: width is not clamped; a peek narrower than the 520 pt live bar can still flicker at its edges.
        if model.mode == .live { g.height = Geo.peek.height }
        model.pointer(inside: (model.hover ? stay : rect(g, s)).contains(p))
        updateMouse()
        s.panel.ignoresMouseEvents = !stay.contains(p)
    }

    private func modelChanged() {
        // No notch anywhere: follow the pointer to another display, but never move a panel that is open or hovered.
        if model.mode == .idle || model.mode == .live || model.showOnAllDisplays != allShown { syncShells() }
        updateMouse()
        for s in shells.values {
            if model.mode == .open, s.id == model.activeDisplay {
                if !s.panel.isKeyWindow { s.panel.makeKey() }
            } else if s.panel.isKeyWindow {
                // No public "resign key": cycling the window hands key status back to the previous app.
                s.panel.orderOut(nil)
                s.panel.orderFrontRegardless()
            }
        }
    }
}

private extension NSScreen {
    var displayID: DisplayID? { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? DisplayID }
}

/// A click on the non-key panel must reach SwiftUI instead of only making the panel key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Canvas the panel hosts (it fills the window); the shell is drawn inside it.
struct NotchRoot: View {
    var model: NotchModel
    var screen: ShellScreen

    var body: some View {
        NotchContainer(model: model, screen: screen)
    }
}
