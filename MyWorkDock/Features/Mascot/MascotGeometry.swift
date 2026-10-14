import AppKit
import ApplicationServices

/// Where the mascot window goes: the character sits on the Dock's Trash, its bubble above-left.
enum MascotGeometry {
    static let window = CGSize(width: 440, height: 460)
    /// The character is drawn centred at this x inside the window, seat on the bottom edge.
    static let characterCenterX: CGFloat = 390
    static let characterSize = CGSize(width: 100, height: 110)
    /// How far the seat sinks into the top of the Trash icon.
    static let seatSink: CGFloat = 14

    /// `trashAX` is in Accessibility (top-left origin) coordinates; the result is a Cocoa window frame.
    static func windowFrame(trashAX: CGRect, primaryHeight: CGFloat) -> CGRect {
        let seatCocoaY = primaryHeight - (trashAX.minY + seatSink)
        return CGRect(x: trashAX.midX - characterCenterX, y: seatCocoaY, width: window.width, height: window.height)
    }

    /// Without Accessibility access: bottom-right, just above the Dock.
    static func fallbackFrame(screen: CGRect, visible: CGRect) -> CGRect {
        CGRect(x: screen.maxX - 48 - characterCenterX, y: visible.minY - seatSink, width: window.width, height: window.height)
    }

    /// The Trash is the last item in the Dock's list. Needs Accessibility access.
    static func trashFrameAX() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = children(app).first(where: { role($0) == kAXListRole as String }),
              let trash = children(list).last else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard let p = attr(trash, kAXPositionAttribute), let s = attr(trash, kAXSizeAttribute),
              AXValueGetValue(p as! AXValue, .cgPoint, &pos), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    static func currentFrame() -> CGRect {
        let primary = NSScreen.screens.first
        if let trash = trashFrameAX(), let primary { return windowFrame(trashAX: trash, primaryHeight: primary.frame.height) }
        let s = NSScreen.main ?? primary
        return fallbackFrame(screen: s?.frame ?? .zero, visible: s?.visibleFrame ?? .zero)
    }

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "allow Accessibility" prompt (once) and opens the right Settings pane.
    static func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    private static func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    private static func role(_ e: AXUIElement) -> String? { attr(e, kAXRoleAttribute) as? String }
}

enum MascotNotes {
    /// "Done: <title>" when a session goes from working to idle.
    static func done(previous: [AgentSession], current: [AgentSession], title: (String) -> String?) -> String? {
        for s in current where s.state == .idle {
            if previous.first(where: { $0.id == s.id })?.state == .working {
                return "Done: \(title(s.transcriptID) ?? s.project)"
            }
        }
        return nil
    }
}
