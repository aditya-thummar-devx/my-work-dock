import Foundation

/// One ring in the right ear. `percent == nil` means the account has no reading.
struct PeekBar: Equatable, Identifiable {
    var label: String
    var percent: Int?
    /// Reset text without the leading ↻; nil renders "idle".
    var reset: String?

    var id: String { label }
    var isHot: Bool { (percent ?? 0) >= 80 }
}

struct PeekData: Equatable {
    var name: String
    /// POOL (a pool member is in use) or SSO (the active saved account).
    var isPool: Bool
    var bars: [PeekBar]

    var initial: String { String(name.prefix(1)).uppercased() }
}

/// What hover can show; Settings › Peek switches them. claudex alone takes the whole hover; otherwise TODO and Clipboard
/// counts share the left of the notch and the Local IP sits on its right. The raw values are stored in UserDefaults.
enum PeekSource: String, CaseIterable, Identifiable {
    case claudex, todo, clipboard, localIP

    /// What is on until the user switches claudex on (which takes the others off) or off again (which puts these back).
    static let defaultOn: Set<PeekSource> = [.todo, .clipboard, .localIP]

    var id: String { rawValue }
    var label: String {
        switch self {
        case .claudex: "claudex usage"
        case .todo: "TODO count"
        case .clipboard: "Clipboard count"
        case .localIP: "Local IP"
        }
    }
    var glyph: Glyph {
        switch self {
        case .claudex: .gauge
        case .todo: .check
        case .clipboard: .clipboard
        case .localIP: .globe
        }
    }
    /// The menu that feeds it: a source whose menu is off never shows.
    var feature: Feature {
        switch self {
        case .claudex: .claudex
        case .todo: .notes
        case .clipboard: .clipboard
        case .localIP: .localIP
        }
    }
}

struct PeekTodo: Hashable {
    var left: Int
    var done: Int
}

struct PeekClips: Hashable {
    var total: Int
    var pinned: Int
}

/// The sources that show beside the notch when claudex is off; one that has nothing to show is nil and its ear part is hidden.
/// Hashable: `PeekMetrics` caches the measured ears per value.
struct PeekInfo: Hashable {
    var todo: PeekTodo?
    var clips: PeekClips?
    var ip: String?

    /// TODO and Clips share the left ear, the IP has the right one; a missing part never moves the others to the other side.
    var hasLeft: Bool { todo != nil || clips != nil }
    var isEmpty: Bool { !hasLeft && ip == nil }

    var spoken: String {
        var parts: [String] = []
        if let todo { parts.append("Todo: \(todo.left) left, \(todo.done) done") }
        if let clips { parts.append("Clipboard: \(clips.total) \(clips.total == 1 ? "clip" : "clips"), \(clips.pinned) pinned") }
        if let ip { parts.append("Local IP \(ip)") }
        return parts.joined(separator: ". ")
    }
}

/// What hover draws: claudex's two ears, the counts and IP around the notch, or the hint when there is nothing to show.
enum PeekContent: Equatable {
    case claudex
    case info(PeekInfo)
    case hint
}
