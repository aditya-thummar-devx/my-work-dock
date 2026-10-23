import Foundation

/// Watches upcoming calendar events and drives the CalendarPeekState machine in NotchModel.
/// - Ticks every 60 seconds (aligned to the minute boundary for responsiveness).
/// - Only raises peek for the soonest event that carries a video join URL.
/// - Manages headsUp → live → shrunk → nil transitions automatically.
@MainActor
final class CalendarAutoPeekScheduler {
    var threshold: Int // minutes before start to fire heads-up
    private weak var calendar: CalendarStore?
    private var timer: Timer?
    /// Called on every state change. `nil` means no peek should show.
    var onState: (CalendarPeekState?) -> Void
    /// The event ID that has been dismissed by the user this session — won't re-show.
    private var dismissedEventIDs: Set<String> = []
    /// The event ID currently being tracked (prevents redundant state recalculations in `changed()`).
    private var trackedEventID: String?

    init(calendar: CalendarStore, threshold: Int, onState: @escaping (CalendarPeekState?) -> Void) {
        self.calendar = calendar
        self.threshold = threshold
        self.onState = onState
    }

    func start() {
        stop()
        // Tick immediately, then every 60 s.
        tick()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called by NotchModel when the user dismisses (✕ / Esc from visible bar, or second Esc from shrunk).
    func dismissCurrent() {
        if let id = trackedEventID { dismissedEventIDs.insert(id) }
        trackedEventID = nil
        onState(nil)
    }

    /// Called by NotchModel when the user shrinks (first Esc / ✕ from visible bar).
    func shrinkCurrent(currentState: CalendarPeekState) {
        guard case .headsUp(let item, _) = currentState else {
            if case .live(let item, _) = currentState {
                onState(.shrunk(item: item, reExpanded: false))
            }
            return
        }
        onState(.shrunk(item: item, reExpanded: false))
    }

    /// Called by NotchModel when the user hovers while shrunk (re-expand) or un-hovers (collapse back).
    func setReExpanded(_ value: Bool, currentState: CalendarPeekState) {
        guard case .shrunk(let item, _) = currentState else { return }
        onState(.shrunk(item: item, reExpanded: value))
    }

    /// The user clicked Join — treat as full dismiss.
    func joined() { dismissCurrent() }

    private func tick() {
        guard let calendar else { return }
        let now = calendar.now()

        // Find the soonest non-dismissed, non-declined timed event with a video URL.
        guard let event = nextEvent(in: calendar, now: now) else {
            // No qualifying event → clear state.
            if trackedEventID != nil {
                trackedEventID = nil
                onState(nil)
            }
            return
        }

        let item = event
        trackedEventID = item.eventID

        let secondsUntilStart = item.start.timeIntervalSince(now)
        let secondsPastStart = now.timeIntervalSince(item.start)
        let secondsUntilEnd = item.end.timeIntervalSince(now)

        // Event has ended.
        if secondsUntilEnd <= 0 {
            dismissedEventIDs.insert(item.eventID)
            trackedEventID = nil
            onState(nil)
            return
        }

        // Event is live (started) but within the T+5-min grace window.
        if secondsUntilStart <= 0 {
            let minutesPastStart = Int(secondsPastStart / 60)
            let minutesLeft = max(0, Int(ceil(secondsUntilEnd / 60)))

            if minutesPastStart >= 5 {
                // Grace window expired → shrink automatically (only if we were showing heads-up or live).
                onState(.shrunk(item: item, reExpanded: false))
            } else {
                onState(.live(item: item, minutesLeft: minutesLeft))
            }
            return
        }

        // Event not started yet — check threshold.
        let minutesUntilStart = Int(ceil(secondsUntilStart / 60))
        if minutesUntilStart <= threshold {
            onState(.headsUp(item: item, minutesLeft: minutesUntilStart))
        } else {
            // Too far out — no state.
            if trackedEventID != nil {
                onState(nil)
            }
        }
    }

    /// Returns the soonest upcoming timed event with a video URL that hasn't been dismissed.
    private func nextEvent(in store: CalendarStore, now: Date) -> CalendarPeekItem? {
        guard let upcoming = store.upcomingToday() else { return nil }
        return upcoming
            .filter { !dismissedEventIDs.contains($0.id) }
            .compactMap { event -> CalendarPeekItem? in
                guard let url = event.meetURL else { return nil }
                return CalendarPeekItem(
                    eventID: event.id,
                    title: event.title,
                    start: event.start,
                    end: event.end,
                    meetURL: url,
                    meetName: event.meetName ?? "Join"
                )
            }
            .min(by: { $0.start < $1.start })
    }
}
