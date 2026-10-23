import SwiftUI

/// The auto-peek bar shown in the notch for upcoming / live meetings.
/// Replaces the standard peek ears when active, matching the 3 states from the design spec:
/// 1. Heads-up (T−N min): NEXT cyan badge, countdown, Join button
/// 2. Live (started, not joined): LIVE red badge, elapsed time, Join button
/// 3. Shrunk: Compact dot beside the notch with elapsed/remaining time
struct CalendarPeekView: View {
    var state: CalendarPeekState
    var onJoin: () -> Void
    var onDismiss: () -> Void
    var onExpand: () -> Void = {}
    @Environment(\.tokens) private var t

    private static let cyan = Color(hex: 0x5CE1E6)
    private static let cyanBg = Color(hex: 0x5CE1E6, opacity: 0.18)
    private static let red = Color(hex: 0xFF6B63)
    private static let redBg = Color(hex: 0xFF6B63, opacity: 0.18)
    private static let green = Color(hex: 0x30D158)
    private static let closeBg = Color(hex: 0x1C1C1E)
    private static let closeFg = Color(hex: 0xA1A1AA)
    private static let subtext = Color(hex: 0x8E8E93)

    var body: some View {
        switch state {
        case .shrunk(let item, let reExpanded):
            if reExpanded {
                fullBar(item: item, isLive: true, badgeText: "LIVE", badgeColor: Self.red, badgeBg: Self.redBg,
                        leftTimeText: liveElapsedText(for: item), iconGlyph: .video, subtitle: liveSubtitle(for: item))
            } else {
                shrunkBar(item: item)
            }
        case .headsUp(let item, let minutesLeft):
            fullBar(item: item, isLive: false, badgeText: "NEXT", badgeColor: Self.cyan, badgeBg: Self.cyanBg,
                    leftTimeText: "in \(minutesLeft) min", iconGlyph: .calendar, subtitle: item.timeLabel)
        case .live(let item, _):
            fullBar(item: item, isLive: true, badgeText: "LIVE", badgeColor: Self.red, badgeBg: Self.redBg,
                    leftTimeText: liveElapsedText(for: item), iconGlyph: .video, subtitle: liveSubtitle(for: item))
        }
    }

    /// Full width peek bar (610 pt): left ear (150 pt), keep-out (200 pt), right ear (~260 pt).
    private func fullBar(item: CalendarPeekItem, isLive: Bool, badgeText: String, badgeColor: Color, badgeBg: Color,
                         leftTimeText: String, iconGlyph: Glyph, subtitle: String) -> some View {
        HStack(spacing: 0) {
            // Left ear: countdown & badge
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(leftTimeText)
                        .font(Typo.ui(13, .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 5, height: 5)
                        Text(badgeText)
                            .font(Typo.ui(9.5, .heavy))
                            .tracking(1)
                            .foregroundStyle(badgeColor)
                    }
                }
                ZStack {
                    Circle()
                        .fill(badgeBg)
                        .frame(width: 26, height: 26)
                    Icon(iconGlyph, size: 14)
                        .foregroundStyle(badgeColor)
                }
            }
            .frame(width: 150, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.leading, 16)

            // Hardware notch keep-out
            Color.clear.frame(width: Geo.keepOutWidth)

            // Right ear: title, subtitle, Join button, Dismiss ✕
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(Typo.ui(13, .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Self.subtext)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Join button
                Button(action: onJoin) {
                    HStack(spacing: 5) {
                        Icon(.video, size: 13, stroke: 2.4)
                        Text("Join")
                            .font(Typo.ui(12.5, .bold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.leading, 9)
                    .padding(.trailing, 11)
                    .frame(height: 28)
                    .background(Capsule().fill(Self.green))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                // Dismiss button (✕)
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Self.closeBg)
                            .frame(width: 24, height: 24)
                        Icon(.close, size: 9, stroke: 3)
                            .foregroundStyle(Self.closeFg)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss meeting peek")
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Geo.calendarPeek.width, height: Geo.peek.height)
        .contentShape(Rectangle())
    }

    /// Shrunk bar (300 pt wide, 32 pt high): dot on the left, keep-out in center, elapsed time on the right.
    private func shrunkBar(item: CalendarPeekItem) -> some View {
        HStack(spacing: 0) {
            // Left dot (44 pt wide)
            HStack {
                Circle()
                    .fill(Self.red)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 44, alignment: .center)

            // Hardware notch keep-out
            Color.clear.frame(width: Geo.keepOutWidth)

            // Right elapsed / remaining text (e.g. "+5m")
            HStack {
                Text(shrunkTimingText(for: item))
                    .font(Typo.mono(11, .semibold))
                    .foregroundStyle(Color(hex: 0xC7C7CC))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: Geo.calendarPeekShrunk.width, height: Geo.calendarPeekShrunk.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityLabel("\(item.title) started. Show meeting peek")
    }

    private func liveElapsedText(for item: CalendarPeekItem) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(item.start) / 60))
        return "\(elapsed) min in"
    }

    private func liveSubtitle(for item: CalendarPeekItem) -> String {
        let remaining = max(0, Int(ceil(item.end.timeIntervalSinceNow / 60)))
        return "\(remaining) min left"
    }

    private func shrunkTimingText(for item: CalendarPeekItem) -> String {
        let now = Date()
        if now < item.start {
            let mins = max(1, Int(ceil(item.start.timeIntervalSince(now) / 60)))
            return "-\(mins)m"
        } else {
            let mins = max(0, Int(now.timeIntervalSince(item.start) / 60))
            return "+\(mins)m"
        }
    }
}
