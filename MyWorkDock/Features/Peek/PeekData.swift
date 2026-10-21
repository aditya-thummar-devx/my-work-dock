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
/// counts share the left of the notch and the Local IP sits on its right. Today's events are not an ear: they add a row under
/// whatever the ears show, so claudex neither switches them off nor locks them. The raw values are stored in UserDefaults.
enum PeekSource: String, CaseIterable, Identifiable {
    case claudex, todo, clipboard, localIP, events

    /// What is on until the user switches claudex on (which takes the others off) or off again (which puts these back).
    /// Today's events are opt-in.
    static let defaultOn: Set<PeekSource> = [.todo, .clipboard, .localIP]

    /// True for the row under the ears, false for the sources that sit beside the notch.
    var isRow: Bool { self == .events }

    /// The saved choice. claudex alone among the ears (an older or hand-edited list may hold more); the row is its own choice.
    static func restored(_ saved: [String]) -> Set<PeekSource> {
        let on = Set(saved.compactMap(PeekSource.init(rawValue:)))
        let ears = on.filter { !$0.isRow }
        return (ears.contains(.claudex) ? [.claudex] : ears).union(on.filter(\.isRow))
    }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .claudex: "claudex usage"
        case .todo: "TODO count"
        case .clipboard: "Clipboard count"
        case .localIP: "Local IP"
        case .events: "Today's events"
        }
    }
    var glyph: Glyph {
        switch self {
        case .claudex: .gauge
        case .todo: .check
        case .clipboard: .clipboard
        case .localIP: .globe
        case .events: .calendar
        }
    }
    /// The menu that feeds it: a source whose menu is off never shows.
    var feature: Feature {
        switch self {
        case .claudex: .claudex
        case .todo: .notes
        case .clipboard: .clipboard
        case .localIP: .localIP
        case .events: .calendar
        }
    }
}

/// One line of the events row: a timed event that is still to come today, or running now.
struct PeekEvent: Hashable, Identifiable {
    var id: String
    var title: String
    var color: UInt32
    var start: Date
    var end: Date
}

/// The row under the ears: the next events today (at most `Geo.Peek.eventsShown`) and how many more there are. With no rows it
/// says nothing is left.
struct PeekEvents: Hashable {
    var rows: [PeekEvent]
    var more: Int
    /// What "now" and "in 25 min" are measured from.
    var now: Date

    /// Divider, padding, the rows (or the one "nothing left" line) and the "+N more" line: what the shell grows by.
    var height: CGFloat {
        Geo.Peek.eventsDivider + Geo.Peek.eventsTop + CGFloat(max(1, rows.count)) * Geo.Peek.eventRow
            + (more > 0 ? Geo.Peek.eventsMore : 0) + Geo.Peek.eventsBottom
    }

    /// "now" once it has started, then "in 25 min", "in 1 h", "in 1 h 5 min". Rounds up: 30 s before 10:30 is "in 1 min".
    static func timing(from start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "in \(minutes / 60) h" : "in \(minutes / 60) h \(rest) min"
    }

    var spoken: String {
        if rows.isEmpty { return "No more events today" }
        let lines = rows.map { "\($0.title), \(Self.timing(from: $0.start, now: now))" }
        return "Today: " + lines.joined(separator: ". ") + (more > 0 ? ". \(more) more" : "")
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
