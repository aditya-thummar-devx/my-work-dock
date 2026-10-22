import SwiftUI

extension Geo {
    enum Btn {
        /// `Refresh` pill beside the sub-tabs.
        static let pillHeight: CGFloat = 32
        static let pillPad = (leading: CGFloat(10), trailing: CGFloat(12))
        static let pillGap: CGFloat = 6
        static let pillFont: CGFloat = 12.5
        /// claudex toolbar buttons.
        static let toolHeight: CGFloat = 28
        static let toolRadius: CGFloat = 9
        static let toolPadX: CGFloat = 10
        static let toolFont: CGFloat = 12
        /// Borderless icon buttons inside list rows.
        static let rowIcon: CGFloat = 30
        static let rowIconRadius: CGFloat = 9
    }
}

/// Round icon button on a `ctrl` fill: pin, settings, search, refresh, close.
struct IconButton: View {
    var glyph: Glyph
    var label: String
    var size: CGFloat = Geo.Chrome.iconButton
    var iconSize: CGFloat = Geo.Chrome.iconButtonIcon
    var stroke: CGFloat?
    var fill: Color?
    var fg: Color?
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            Icon(glyph, size: iconSize, stroke: stroke)
                .foregroundStyle(fg ?? t.text2)
                .frame(width: size, height: size)
                .background(Circle().fill(fill ?? t.ctrl))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Borderless rounded-square icon button in list rows: edit (muted), delete (red), cancel edit (`btn2`).
struct RowIconButton: View {
    var glyph: Glyph
    var label: String
    var fg: Color
    var fill: Color = .clear
    var iconSize: CGFloat = 14
    var stroke: CGFloat?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Icon(glyph, size: iconSize, stroke: stroke)
                .foregroundStyle(fg)
                .frame(width: Geo.Btn.rowIcon, height: Geo.Btn.rowIcon)
                .background(RoundedRectangle(cornerRadius: Geo.Btn.rowIconRadius).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// `⟳ Refresh`: capsule on `ctrl` with an icon and a label.
struct PillButton: View {
    var title: String
    var glyph: Glyph
    var iconSize: CGFloat = 14
    var stroke: CGFloat?
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            HStack(spacing: Geo.Btn.pillGap) {
                Icon(glyph, size: iconSize, stroke: stroke)
                Text(title).font(Typo.ui(Geo.Btn.pillFont, .semibold))
            }
            .foregroundStyle(t.text)
            .padding(.leading, Geo.Btn.pillPad.leading)
            .padding(.trailing, Geo.Btn.pillPad.trailing)
            .frame(height: Geo.Btn.pillHeight)
            .background(Capsule().fill(t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// claudex toolbar button: 28 pt tall, radius 9, `ctrl` fill. The caller supplies the content
/// (checkbox + label, `Sort <value> ⌄`, dot + label, plain text).
struct ToolButton<Content: View>: View {
    var fill: Color?
    var fg: Color?
    var padLeading: CGFloat = Geo.Btn.toolPadX
    var padTrailing: CGFloat = Geo.Btn.toolPadX
    var enabled = true
    var action: () -> Void = {}
    @ViewBuilder var content: Content
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: action) {
            content
                .font(Typo.ui(Geo.Btn.toolFont, .semibold))
                .foregroundStyle(fg ?? t.text)
                .padding(.leading, padLeading)
                .padding(.trailing, padTrailing)
                .frame(height: Geo.Btn.toolHeight)
                .background(RoundedRectangle(cornerRadius: Geo.Btn.toolRadius).fill(fill ?? t.ctrl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Dot toggle in the claudex toolbar: `● Start pool`, green tint when on.
struct DotToolButton: View {
    var title: String
    var on: Bool
    var enabled = true
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        ToolButton(fill: on ? t.gaugeGreen.opacity(0.14) : t.ctrl, fg: !enabled ? t.offFg : on ? t.green : t.text, enabled: enabled, action: action) {
            HStack(spacing: 6) {
                Circle().fill(on ? t.gaugeGreen : t.offFg).frame(width: 6, height: 6)
                Text(title)
            }
        }
    }
}

// MARK: - Action buttons

/// Size and type of an action button. The designs use a handful of fixed combinations.
struct ButtonMetrics {
    var height: CGFloat
    var radius: CGFloat
    var padLeading: CGFloat
    var padTrailing: CGFloat
    var font: CGFloat
    var gap: CGFloat = 6
    var width: CGFloat?

    /// Remove / Switch / Deny / View details on claudex cards.
    static let card = ButtonMetrics(height: 24, radius: 8, padLeading: 10, padTrailing: 10, font: 11.5)
    /// Play / Stop / Cold boot on device cards.
    static let device = ButtonMetrics(height: 30, radius: 10, padLeading: 10, padTrailing: 12, font: 12.5)
    /// Add (commands field).
    static let add = ButtonMetrics(height: 32, radius: 10, padLeading: 12, padTrailing: 12, font: 12.5)
    /// Save (inline command edit).
    static let save = ButtonMetrics(height: 30, radius: 9, padLeading: 12, padTrailing: 12, font: 12)
    /// Cancel / Confirm in the confirm sheet.
    static let confirm = ButtonMetrics(height: 32, radius: 10, padLeading: 12, padTrailing: 12, font: 12.5)
    /// Connect / Disconnect / Retry on wireless cards; 86 pt so a `Disconnected` pill still fits beside it in a 230 pt card.
    static let wireless = ButtonMetrics(height: 30, radius: 10, padLeading: 0, padTrailing: 0, font: 12.5, width: 86)
    /// Copy in command rows.
    static let copy = ButtonMetrics(height: 30, radius: 9, padLeading: 10, padTrailing: 10, font: 12)
    /// Copy in the tunnel command well.
    static let well = ButtonMetrics(height: 32, radius: 10, padLeading: 10, padTrailing: 10, font: 12)
    /// Refresh / show raw in the details sheet.
    static let sheet = ButtonMetrics(height: 30, radius: 10, padLeading: 12, padTrailing: 12, font: 12.5)
    /// Clear (playground output header).
    static let clear = ButtonMetrics(height: 26, radius: 8, padLeading: 10, padTrailing: 10, font: 11.5)
    /// Full-width form buttons: Pair / Open Devices window (36) and Run reverse tunnel (44).
    static let form = ButtonMetrics(height: 36, radius: 12, padLeading: 0, padTrailing: 0, font: 13)
    static let run = ButtonMetrics(height: 44, radius: 14, padLeading: 0, padTrailing: 0, font: 14, gap: 8)
}

enum ButtonTone {
    case tint            // tint fill, black text
    case secondary       // btn2, text
    case secondaryQuiet  // btn2, text2
    case ctrl            // ctrl, text2
    case outline(Color?) // 1 pt border, given text colour (nil = text)
    case danger          // #E5484D, white text
    case stop            // red tint, red text
    case copied          // green tint, green text
    case off             // disabled: btnOff, offFg
    case offOnCtrl       // disabled on a btn2 fill (cold boot while booting)

    func colors(_ t: Tokens) -> (fill: Color, fg: Color, border: Color?) {
        switch self {
        case .tint: (t.accent, Tokens.onTint, nil)
        case .secondary: (t.btn2, t.text, nil)
        case .secondaryQuiet: (t.btn2, t.text2, nil)
        case .ctrl: (t.ctrl, t.text2, nil)
        case .outline(let fg): (.clear, fg ?? t.text, t.border)
        case .danger: (Fixed.danger, Fixed.onDanger, nil)
        case .stop: (t.redBg, t.red, nil)
        case .copied: (t.greenBg, t.green, nil)
        case .off: (t.btnOff, t.offFg, nil)
        case .offOnCtrl: (t.btn2, t.offFg, nil)
        }
    }
}

/// Turning refresh glyph for work in flight; the colour comes from `foregroundStyle`. Holds still in snapshots.
struct Spinner: View {
    var size: CGFloat = 13
    var stroke: CGFloat? = 2.4
    @Environment(\.staticRender) private var staticRender
    @State private var spinning = false

    var body: some View {
        Icon(.refresh, size: size, stroke: stroke)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                guard !staticRender else { return }
                withAnimation(.linear(duration: Geo.IPChip.spin).repeatForever(autoreverses: false)) { spinning = true }
            }
            .onDisappear { spinning = false }
            .accessibilityLabel("Loading")
    }
}

/// The shared action button: tint / secondary / outlined / destructive, with an optional leading icon.
/// `busy` swaps the icon for a spinner and disables the button.
struct DockButton: View {
    var title: String
    var glyph: Glyph?
    var iconSize: CGFloat = 12
    var iconStroke: CGFloat?
    var metrics: ButtonMetrics
    var tone: ButtonTone
    var weight: Font.Weight = .semibold
    var enabled = true
    var busy = false
    var action: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        let c = tone.colors(t)
        Button(action: action) {
            HStack(spacing: metrics.gap) {
                if busy { Spinner(size: iconSize, stroke: iconStroke) } else if let glyph { Icon(glyph, size: iconSize, stroke: iconStroke) }
                Text(title)
            }
            .font(Typo.ui(metrics.font, weight))
            .foregroundStyle(c.fg)
            .padding(.leading, metrics.padLeading)
            .padding(.trailing, metrics.padTrailing)
            .frame(width: metrics.width, height: metrics.height)
            .frame(maxWidth: metrics.width == nil && metrics.padLeading == 0 ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: metrics.radius).fill(c.fill))
            .overlay {
                if let border = c.border {
                    RoundedRectangle(cornerRadius: metrics.radius).strokeBorder(border, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}
