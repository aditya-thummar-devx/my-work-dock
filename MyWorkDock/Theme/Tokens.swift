import SwiftUI

// Mirrors DESIGN_SPEC §2, plus the tokens Prototype.dc.html uses that the spec omits
// (hot, platOn/platOnFg, popShadow; `editRing` is identical to `ink` so it isn't duplicated).
// Source of truth for values: Prototype.dc.html `renderVals()` colour table.

extension Color {
    /// sRGB hex with optional alpha, e.g. `Color(hex: 0xFFFFFF, opacity: 0.07)` for `rgba(255,255,255,.07)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Settings › Appearance › Theme. `Tokens` only ever gets a resolved `.dark` or `.light`.
enum ThemeMode: String, CaseIterable {
    case system, dark, light

    /// What the UI is drawn in: `.system` follows macOS.
    func resolved(systemIsDark: Bool) -> ThemeMode {
        self == .system ? (systemIsDark ? .dark : .light) : self
    }
}

/// Settings › Appearance tints. Text on a tint is always `Tokens.onTint`.
enum Tint: String, CaseIterable, Identifiable {
    case lime, blue, purple, pink, orange, yellow, green, teal

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var color: Color { Color(hex: hex) }

    /// The tint darkened, for a light surface: lime or yellow at full strength all but vanish on it.
    var shade: Color {
        func channel(_ shift: UInt32) -> Double { Double((hex >> shift) & 0xFF) / 255 * 0.55 }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0))
    }

    var hex: UInt32 {
        switch self {
        case .lime: 0xD4FF3A
        case .blue: 0x0A84FF
        case .purple: 0xBF5AF2
        case .pink: 0xFF375F
        case .orange: 0xFF9F0A
        case .yellow: 0xFFD60A
        case .green: 0x30D158
        case .teal: 0x64D2FF
        }
    }
}

struct Tokens {
    let mode: ThemeMode
    let tint: Tint

    // Surfaces
    let panel, ctrl, card, list, listLine, inset, btn2, btnOff: Color
    // Text
    let text, text2, muted, faint, offFg, ring: Color
    // Strokes and overlays
    let line, border, subOn, pop, track, scrim: Color
    /// `popShadow`: colour only; geometry is `Geo.Chrome.popoverShadow*`.
    let popShadow: Color
    // Gauge bar fills
    let gaugeGreen, gaugeAmber, gaugeRed: Color
    // Status foreground / background pairs
    let green, greenBg, boot, bootBg, orange, orangeBg, red, redBg, gray, grayBg: Color
    /// Overdue / due-today text.
    let hot: Color
    /// Active platform-segment fill and its text.
    let platOn, platOnFg: Color

    var isDark: Bool { mode == .dark }
    var accent: Color { tint.color }
    /// `$` prompts, + icons, edit ring: the tint is unreadable on the light panel.
    var ink: Color { isDark ? tint.color : Color(hex: 0x111114) }
    /// The notch buddy, drawn on the shell: the tint on the black one, its darker shade on the light one.
    var buddy: Color { isDark ? tint.color : tint.shade }
    /// Text and icons on top of `accent`.
    static let onTint = Color.black

    init(mode: ThemeMode, tint: Tint) {
        self.mode = mode
        self.tint = tint
        let d = mode == .dark
        func p(_ dark: Color, _ light: Color) -> Color { d ? dark : light }
        func c(_ hex: UInt32, _ a: Double = 1) -> Color { Color(hex: hex, opacity: a) }

        panel = p(c(0x000000), c(0xF2F2F6))
        ctrl = p(c(0x1C1C1E), c(0xE4E4EA))
        card = p(c(0x141416), c(0xFFFFFF))
        list = p(c(0x111113), c(0xFFFFFF))
        listLine = p(.clear, c(0x000000, 0.06))
        inset = p(c(0x0B0B0C), c(0xF2F2F6))
        btn2 = p(c(0x1F1F23), c(0xEDEDF1))
        btnOff = p(c(0x1A1A1D), c(0xF0F0F3))

        text = p(c(0xF5F5F7), c(0x111114))
        text2 = p(c(0xC7C7CC), c(0x3A3A40))
        muted = p(c(0xA1A1AA), c(0x55555C))
        faint = p(c(0x8E8E93), c(0x6B6B73))
        offFg = p(c(0x5A5A60), c(0xAEAEB6))
        ring = p(c(0x48484A), c(0xC2C2C8))

        line = p(c(0xFFFFFF, 0.07), c(0x000000, 0.07))
        border = p(c(0xFFFFFF, 0.12), c(0x000000, 0.12))
        subOn = p(c(0xFFFFFF, 0.12), c(0xFFFFFF))
        pop = p(c(0x1C1C1E), c(0xFFFFFF))
        track = p(c(0xFFFFFF, 0.10), c(0x000000, 0.08))
        scrim = p(c(0x000000, 0.45), c(0x000000, 0.18))
        popShadow = p(c(0x000000, 0.6), c(0x000000, 0.22))

        gaugeGreen = p(c(0x30D158), c(0x2E9E4A))
        gaugeAmber = p(c(0xE0A100), c(0xC98A00))
        gaugeRed = p(c(0xE5484D), c(0xD93A2F))

        green = p(c(0x4ADE80), c(0x1B8A43))
        greenBg = c(0x30D158, 0.16)
        boot = p(c(0xC9B8FF), c(0x5B3FD1))
        bootBg = p(c(0xB69CFF, 0.18), c(0x7C5CFF, 0.14))
        orange = p(c(0xFFB340), c(0xA45A00))
        orangeBg = p(c(0xFF9F0A, 0.16), c(0xFF9F0A, 0.18))
        red = p(c(0xFF8A8A), c(0xC62F2F))
        redBg = p(c(0xFF6B6B, 0.16), c(0xFF3B30, 0.12))
        gray = p(c(0xA1A1AA), c(0x55555C))
        grayBg = p(c(0xFFFFFF, 0.08), c(0x000000, 0.06))

        hot = p(c(0xFF9F5A), c(0xC2500A))
        platOn = p(c(0xF5F5F7), c(0xFFFFFF))
        platOnFg = p(c(0x000000), c(0x111114))
    }

    /// Gauge rule: < 50 % green, 50–79 % amber, ≥ 80 % red.
    func gaugeColor(_ percent: Int) -> Color {
        percent >= 80 ? gaugeRed : percent >= 50 ? gaugeAmber : gaugeGreen
    }
}

extension EnvironmentValues {
    @Entry var tokens = Tokens(mode: .dark, tint: .lime)
}

// MARK: - Colours that don't change with theme or tint

enum Fixed {
    /// Hardware-notch black. The shell itself fills with `Tokens.panel` (black in dark, light grey in light).
    static let shell = Color.black
    static let runningDot = Color(hex: 0x30D158)

    // Peek (on black in dark theme; light theme uses Tokens)
    static let peekText = Color(hex: 0xF5F5F7)
    static let peekLabelHot = Color(hex: 0xFF6B6B)
    static let peekRingTrack = Color(hex: 0xFFFFFF, opacity: 0.14)
    static let poolFg = Color(hex: 0x5CE1E6)
    /// Pool text on the light shell, where the cyan is unreadable.
    static let poolFgLight = Color(hex: 0x0B7F86)
    static let poolBg = Color(hex: 0x5CE1E6, opacity: 0.18)
    static let ssoBg = Color(hex: 0xC9B8FF, opacity: 0.2)

    // Live activity (on black in dark theme; light theme uses Tokens)
    static let liveTrack = Color(hex: 0xFFFFFF, opacity: 0.12)

    // Components (Prototype.dc.html inline styles)
    /// Destructive confirm button fill and its white text, in both themes.
    static let danger = Color(hex: 0xE5484D)
    static let onDanger = Color.white
    /// `input::placeholder` colour.
    static let placeholder = Color(hex: 0x8A8A92)
    /// Running device card border and glow (`rgba(48,209,88,…)`).
    static let runningBorder = Color(hex: 0x30D158, opacity: 0.45)
    static let runningGlow = Color(hex: 0x30D158, opacity: 0.08)
    /// Tint swatch resting outline.
    static let swatchLine = Color.black.opacity(0.12)
    /// Settings theme-card miniatures: fixed per theme, independent of the current theme.
    /// System is split down the middle, dark left and light right, with a mid-grey bar that reads on both.
    static func themePreview(_ mode: ThemeMode) -> (fill: AnyShapeStyle, line: Color, bar: Color) {
        switch mode {
        case .dark:
            (AnyShapeStyle(Color(hex: 0x000000)), Color(hex: 0xFFFFFF, opacity: 0.12), Color(hex: 0x2A2A2E))
        case .light:
            (AnyShapeStyle(Color(hex: 0xF2F2F6)), Color.black.opacity(0.10), Color(hex: 0xDADAE0))
        case .system:
            (AnyShapeStyle(LinearGradient(stops: [.init(color: Color(hex: 0x000000), location: 0.5), .init(color: Color(hex: 0xF2F2F6), location: 0.5)],
                                          startPoint: .leading, endPoint: .trailing)),
             Color(hex: 0xFFFFFF, opacity: 0.12), Color(hex: 0x7C7C84))
        }
    }
}

/// Todo tag colours (DESIGN_SPEC §5; backgrounds from Prototype `tagBgs`). Tags the designs don't know get the
/// colour the user's `New tag` was created with (`custom`), else a neutral grey.
enum TagPalette {
    static func color(_ tag: String) -> Color? {
        switch tag {
        case "release": Color(hex: 0xD4FF3A)
        case "bug": Color(hex: 0xFF8A8A)
        case "deps", "client": Color(hex: 0x5CE1E6)
        case "docs": Color(hex: 0xC9B8FF)
        case "idea": Color(hex: 0xFF8AD8)
        default: nil
        }
    }

    /// Neutral chip for tags without a colour.
    static let neutral = Color(hex: 0xE5E5EA)

    /// Colour of a tag's dot and of the tag / filter buttons (Prototype `tcol`).
    static func dot(_ tag: String, custom: Color? = nil, in t: Tokens) -> Color {
        custom ?? color(tag) ?? (t.isDark ? neutral : Color(hex: 0xC2C2C8))
    }

    /// Fill and text of a tag / filter button: dark = colour at 16 % with coloured text, light = solid colour with dark text.
    static func button(_ tag: String, custom: Color? = nil, in t: Tokens) -> (bg: Color, fg: Color) {
        let c = dot(tag, custom: custom, in: t)
        return t.isDark ? (c.opacity(0.16), c) : (c, Color(hex: 0x111114))
    }

    /// Dark-theme chip background: the tag colour at ~15 %.
    private static func tint(_ tag: String) -> Color? {
        switch tag {
        case "release": Color(hex: 0xD4FF3A, opacity: 0.14)
        case "bug": Color(hex: 0xFF8A8A, opacity: 0.15)
        case "deps", "client": Color(hex: 0x5CE1E6, opacity: 0.14)
        case "docs": Color(hex: 0xB69CFF, opacity: 0.16)
        case "idea": Color(hex: 0xFF8AD8, opacity: 0.15)
        default: nil
        }
    }

    /// Todo-row chip. Dark: coloured text on a tinted fill. Light: black text on the solid tag colour.
    /// Unknown tags without a custom colour use the neutral fallback. A colour the user picked wins over the name's.
    static func chip(_ tag: String, custom: Color? = nil, in t: Tokens) -> (fg: Color, bg: Color) {
        if t.isDark {
            return (custom ?? color(tag) ?? neutral, custom?.opacity(0.16) ?? tint(tag) ?? Color(hex: 0xFFFFFF, opacity: 0.1))
        }
        return (Color(hex: 0x111114), custom ?? color(tag) ?? Color(hex: 0xE4E4EA))
    }
}
