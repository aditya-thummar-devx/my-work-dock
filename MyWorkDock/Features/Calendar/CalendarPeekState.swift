import Foundation

/// One event that the auto-peek is currently tracking: only raised for events that carry a video join URL.
struct CalendarPeekItem: Equatable {
    var eventID: String
    var title: String
    var start: Date
    var end: Date
    var meetURL: URL
    /// "Google Meet", "Zoom", etc.; falls back to "Join" when unavailable.
    var meetName: String

    /// The time-range subtitle shown in the peek bar: "11:30 – 12:00 · Google Meet".
    var timeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end)) · \(meetName)"
    }
}

/// The three states the auto-peek can be in for a given event.
enum CalendarPeekState: Equatable {
    /// State 01 — Heads-up: auto-opened T−N min before the event starts.
    case headsUp(item: CalendarPeekItem, minutesLeft: Int)
    /// State 02 — Live: event has started and the user has not joined yet.
    case live(item: CalendarPeekItem, minutesLeft: Int)
    /// State 03 — Shrunk: user dismissed the bar (Esc / ✕); a red dot stays beside the notch.
    /// `reExpanded` is true while the user hovers the notch and the bar is temporarily re-shown.
    case shrunk(item: CalendarPeekItem, reExpanded: Bool)

    var item: CalendarPeekItem {
        switch self {
        case .headsUp(let item, _): item
        case .live(let item, _): item
        case .shrunk(let item, _): item
        }
    }

    /// True while the bar should be fully visible (not collapsed to a dot).
    var isVisible: Bool {
        switch self {
        case .headsUp, .live: true
        case .shrunk(_, let re): re
        }
    }

    /// True for the red dot shown beside the notch when shrunk.
    var isShrunk: Bool {
        if case .shrunk = self { return true }
        return false
    }
}
