import SwiftUI

extension Geo {
    enum Chip {
        // Todo tag chip
        static let tagFont: CGFloat = 11
        static let tagPadX: CGFloat = 8
        static let tagPadY: CGFloat = 3
        // Count badge in sub-tabs
        static let badgeMin: CGFloat = 18
        static let badgeHeight: CGFloat = 18
        static let badgePadX: CGFloat = 5
        static let badgeFont: CGFloat = 11
        // Tunnel preset chip
        static let presetHeight: CGFloat = 28
        static let presetPadX: CGFloat = 11
        static let presetFont: CGFloat = 12
        // Health chip / playground option chip
        static let healthHeight: CGFloat = 24
        static let healthPadX: CGFloat = 10
        static let healthFont: CGFloat = 11.5
        static let optionPadX: CGFloat = 9
        // Status pill
        static let pillHeight: CGFloat = 22
        static let pillPadX: CGFloat = 9
        static let pillGap: CGFloat = 6
        static let pillDot: CGFloat = 6
        static let pillFont: CGFloat = 11.5
        // Checkboxes
        static let checkbox: CGFloat = 14
        static let checkboxRadius: CGFloat = 4
        static let checkboxBorder: CGFloat = 1.5
        static let roundCheck: CGFloat = 22
        static let roundCheckBorder: CGFloat = 2
    }
}

/// `#release` chip on a todo row: tag colour text on a tinted fill (dark) or black text on the solid colour (light).
struct TagChip: View {
    var tag: String
    /// Colour of a user-created tag.
    var custom: Color?
    @Environment(\.tokens) private var t

    var body: some View {
        let c = TagPalette.chip(tag, custom: custom, in: t)
        Text("#\(tag)")
            .font(Typo.ui(Geo.Chip.tagFont, .semibold))
            .foregroundStyle(c.fg)
            .padding(.horizontal, Geo.Chip.tagPadX)
            .padding(.vertical, Geo.Chip.tagPadY)
            .background(Capsule().fill(c.bg))
    }
}

/// Count in a sub-tab: tint fill when its tab is active, grey otherwise.
struct CountBadge: View {
    var count: Int
    var on: Bool
    @Environment(\.tokens) private var t

    var body: some View {
        Text("\(count)")
            .font(Typo.ui(Geo.Chip.badgeFont, .bold))
            .foregroundStyle(on ? Tokens.onTint : t.muted)
            .padding(.horizontal, Geo.Chip.badgePadX)
            .frame(minWidth: Geo.Chip.badgeMin, minHeight: Geo.Chip.badgeHeight)
            .frame(height: Geo.Chip.badgeHeight)
            .background(Capsule().fill(on ? t.accent : t.grayBg))
    }
}

/// Tunnel preset: `Metro 8081`. Active = inverted (text fill, panel text).
struct PresetChip: View {
    var label: String
    var port: String
    var on: Bool
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(Typo.ui(Geo.Chip.presetFont, .semibold))
                Text(port).font(Typo.mono(Geo.Chip.presetFont, .medium)).opacity(0.7)
            }
            .foregroundStyle(on ? t.panel : t.text2)
            .padding(.horizontal, Geo.Chip.presetPadX)
            .frame(height: Geo.Chip.presetHeight)
            .background(Capsule().fill(on ? t.text : t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Health summary chip: `sharing on` (green, outlined) or `consuming off` (grey).
struct HealthChip: View {
    enum Tone { case on, off, neutral }
    var text: String
    var tone: Tone
    @Environment(\.tokens) private var t

    var body: some View {
        let (bg, fg, border): (Color, Color, Color) = switch tone {
        case .on: (t.gaugeGreen.opacity(0.14), t.green, t.gaugeGreen.opacity(0.5))
        case .off: (t.grayBg, t.muted, .clear)
        case .neutral: (t.grayBg, t.text2, .clear)
        }
        Text(text)
            .font(Typo.ui(Geo.Chip.healthFont, .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, Geo.Chip.healthPadX)
            .frame(height: Geo.Chip.healthHeight)
            .background(Capsule().fill(bg))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
}

/// Playground command option: mono label on a `ctrl` (or red) pill.
struct OptionChip: View {
    var label: String
    var danger = false
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typo.mono(Geo.Chip.healthFont, .semibold))
                .foregroundStyle(danger ? t.red : t.text)
                .padding(.horizontal, Geo.Chip.optionPadX)
                .frame(height: Geo.Chip.healthHeight)
                .background(Capsule().fill(danger ? t.redBg : t.ctrl))
        }
        .buttonStyle(.plain)
    }
}

/// `giver` / `taker` pill in the member details sheet.
struct RoleChip: View {
    var text: String
    var color: Color
    @Environment(\.tokens) private var t

    var body: some View {
        Text(text)
            .font(Typo.ui(11, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color == t.green ? t.greenBg : t.redBg))
    }
}

enum PillKind {
    case running, booting, stopped, connected, disconnected, unavailable

    var label: String {
        switch self {
        case .running: "Running"
        case .booting: "Booting…"
        case .stopped: "Stopped"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .unavailable: "Unavailable"
        }
    }

    func colors(_ t: Tokens) -> (bg: Color, fg: Color) {
        switch self {
        case .running, .connected: (t.greenBg, t.green)
        case .booting: (t.bootBg, t.boot)
        case .stopped, .unavailable: (t.grayBg, t.gray)
        case .disconnected: (t.orangeBg, t.orange)
        }
    }
}

/// Device / connection status: `● Running`. Booting pulses (static in snapshots).
struct StatusPill: View {
    var kind: PillKind
    @Environment(\.tokens) private var t
    @Environment(\.entrance) private var entrance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    private var animates: Bool { entrance && !reduceMotion }

    var body: some View {
        let c = kind.colors(t)
        HStack(spacing: Geo.Chip.pillGap) {
            Circle().fill(c.fg)
                .frame(width: Geo.Chip.pillDot, height: Geo.Chip.pillDot)
                .opacity(kind == .booting && animates && dim ? 0.35 : 1)
            Text(kind.label)
        }
        .font(Typo.ui(Geo.Chip.pillFont, .semibold))
        .foregroundStyle(c.fg)
        .padding(.horizontal, Geo.Chip.pillPadX)
        .frame(height: Geo.Chip.pillHeight)
        .background(Capsule().fill(c.bg))
        .onAppear {
            guard kind == .booting, animates else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

/// Small square checkbox (claudex "5x only").
struct Checkbox: View {
    var on: Bool
    @Environment(\.tokens) private var t

    var body: some View {
        RoundedRectangle(cornerRadius: Geo.Chip.checkboxRadius)
            .fill(on ? t.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: Geo.Chip.checkboxRadius)
                .strokeBorder(t.muted, lineWidth: on ? 0 : Geo.Chip.checkboxBorder))
            .overlay { if on { Icon(.check, size: 10, stroke: 3.6).foregroundStyle(Tokens.onTint) } }
            .frame(width: Geo.Chip.checkbox, height: Geo.Chip.checkbox)
    }
}

/// Round todo checkbox: ring when open, tint fill with a check when done.
struct RoundCheck: View {
    var done: Bool
    /// What the row is, for VoiceOver ("Mark done: Ship build").
    var title = ""
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(done ? t.accent : .clear)
                .overlay(Circle().strokeBorder(t.ring, lineWidth: done ? 0 : Geo.Chip.roundCheckBorder))
                .overlay { if done { Icon(.check, size: 12, stroke: 3.4).foregroundStyle(Tokens.onTint) } }
                .frame(width: Geo.Chip.roundCheck, height: Geo.Chip.roundCheck)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((done ? "Mark not done" : "Mark done") + (title.isEmpty ? "" : ": \(title)"))
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}
