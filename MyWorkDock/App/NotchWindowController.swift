import AppKit
import SwiftUI

/// Owns the panel: positions it on the notch screen, feeds pointer position to the model, and keeps
/// `ignoresMouseEvents` so clicks outside the drawn shape fall through to apps underneath.
@MainActor
final class NotchWindowController {
    /// Big enough for the open shell (760 + shoulders) and its `0 24 70` shadow.
    static let panelSize = CGSize(width: 960, height: 600)
    /// The cursor can sit exactly on the screen's top edge; extend hit rects upward so it still counts.
    private static let topSlop: CGFloat = 2

    let model: NotchModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var centerX: CGFloat = 0
    private var topY: CGFloat = 0

    init(model: NotchModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        let host = FirstMouseHostingView(rootView: NotchRoot(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.onEscape = { [weak model] in model?.closePanel() }

        reposition()
        panel.orderFrontRegardless()
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
        // ⌘F opens search in the visible Notes tab; Tab cycles the main menu, Shift+Tab its sub-tabs (not while typing in a field).
        // The panel has no menu bar to carry either shortcut.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.panel.isKeyWindow, self.model.mode == .open else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 48, flags.isEmpty || flags == .shift, !(self.panel.firstResponder is NSText) {
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
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    // MARK: Placement

    /// The screen with a notch; with none, the screen the pointer is on (so an external display works), else the main one.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
    }

    /// Frame of the screen the panel currently sits on.
    private var placedOn: CGRect?

    private func reposition() {
        guard let screen = targetScreen else { return }
        var cx = screen.frame.midX
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            cx = (l.maxX + r.minX) / 2
            NSLog("MyWorkDock: hardware notch %.0f pt wide, %.0f pt tall, centre x %.1f",
                  r.minX - l.maxX, screen.safeAreaInsets.top, cx)
            model.setNotch(CGSize(width: r.minX - l.maxX, height: screen.safeAreaInsets.top))
        } else {
            model.setNotch(nil)
            NSLog("MyWorkDock: no hardware notch on this screen; drawing a %.0f x %.0f pill", Geo.idle.width, Geo.idle.height)
        }
        centerX = cx
        topY = screen.frame.maxY
        placedOn = screen.frame
        let size = Self.panelSize
        panel.setFrame(NSRect(x: cx - size.width / 2, y: topY - size.height, width: size.width, height: size.height),
                       display: true)
    }

    // MARK: Pointer and key status

    /// Screen-space rect of the shell for `g`.
    private func rect(_ g: ShellGeometry) -> NSRect {
        NSRect(x: centerX + g.centerOffset - g.width / 2, y: topY - g.height,
               width: g.width, height: g.height + Self.topSlop)
    }

    private func pointerMoved() {
        let p = NSEvent.mouseLocation
        var g = model.geometry
        let stay = rect(g)
        // While only the live activity is showing, entering is limited to peek height, otherwise the
        // 48 → 70 pt height change makes the shell flicker between peek and live under a resting pointer.
        // ponytail: width is not clamped; a peek narrower than the 520 pt live bar can still flicker at its edges.
        if model.mode == .live { g.height = Geo.peek.height }
        model.pointer(inside: (model.hover ? stay : rect(g)).contains(p))
        panel.ignoresMouseEvents = !stay.contains(p)
    }

    private func modelChanged() {
        // No notch anywhere: follow the pointer to another display, but never move a panel that is open or hovered.
        if model.mode == .idle || model.mode == .live, let screen = targetScreen, screen.frame != placedOn { reposition() }
        panel.ignoresMouseEvents = !rect(model.geometry).contains(NSEvent.mouseLocation)
        if model.mode == .open {
            if !panel.isKeyWindow { panel.makeKey() }
        } else if panel.isKeyWindow {
            // No public "resign key": cycling the window hands key status back to the previous app.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}

/// A click on the non-key panel must reach SwiftUI instead of only making the panel key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Fixed-size canvas the panel hosts; the shell is drawn inside it.
struct NotchRoot: View {
    var model: NotchModel

    var body: some View {
        NotchContainer(model: model)
            .frame(width: NotchWindowController.panelSize.width,
                   height: NotchWindowController.panelSize.height, alignment: .top)
    }
}
