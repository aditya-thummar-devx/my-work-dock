import AppKit

/// Borderless, non-activating panel that floats over the menu bar at the top centre of the notch screen.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the shadow is drawn in SwiftUI
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        // `modelChanged` cycles orderOut/orderFront to drop key status; the default hide fade would swallow the shell's shrink.
        animationBehavior = .none
    }

    /// Called for an Esc nothing in the responder chain handled (inline edits, search and the confirm sheet take theirs first).
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    /// Esc from a text view whose delegate declined it.
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// Text fields need a key window while open.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise push the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
