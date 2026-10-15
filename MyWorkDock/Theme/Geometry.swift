import SwiftUI

// Sizes and timings from DESIGN_SPEC §1/§3/§4, cross-checked against Prototype.dc.html inline styles.
// px in the designs = points here. Shoulders are drawn OUTSIDE the stated widths.

enum NotchMode: Equatable {
    case idle, peek, live, open

    /// Size order for picking the shell curve; live shares idle's rank because booting only ever toggles between them.
    var rank: Int {
        switch self {
        case .idle, .live: 0
        case .peek: 1
        case .open: 2
        }
    }
}

/// Settings › Appearance › Panel size: how big the open panel is. The raw values are stored in UserDefaults.
enum PanelSize: String, CaseIterable, Identifiable {
    case medium, large

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Medium is the designed `Geo.open`; large is 75 % of the display (never smaller than medium, and medium when the display is unknown).
    func size(on display: CGSize?) -> CGSize {
        let medium = CGSize(width: Geo.open.width, height: Geo.open.height)
        guard self == .large, let display else { return medium }
        return CGSize(width: max(medium.width, (display.width * 0.75).rounded()), height: max(medium.height, (display.height * 0.75).rounded()))
    }
}

enum Geo {
    // MARK: Shell silhouettes (width, height, bottom radius)

    static let shoulder: CGFloat = 16
    /// Hardware-notch keep-out: centred, nothing interactive inside.
    static let keepOutWidth: CGFloat = 200
    static let keepOutHeight: CGFloat = 32

    /// Idle size when no connected screen has a hardware notch; otherwise idle is a notch's own size (`ShellScreen.idleNotch`).
    static let idle = (width: CGFloat(190), height: CGFloat(32), radius: CGFloat(14))
    /// Idle corners matching the physical notch (~4 pt top flare, ~8 pt bottom; Apple publishes no radii, tune by eye).
    static let hardwareNotch = (shoulder: CGFloat(4), radius: CGFloat(8))
    /// Peek width is not fixed: `keepOutWidth + leftEar + rightEar`, ears hug their content.
    static let peek = (height: CGFloat(48), radius: CGFloat(22))
    static let live = (width: CGFloat(520), height: CGFloat(70), radius: CGFloat(26))
    static let open = (width: CGFloat(760), height: CGFloat(480), radius: CGFloat(36))

    // MARK: Motion

    /// Shell size / radius / offset: cubic-bezier(0.32, 0.72, 0, 1) over 0.5 s.
    static let shellDuration = 0.5
    static let shellCurve = (x1: 0.32, y1: 0.72, x2: 0.0, y2: 1.0)
    /// Shrinking (open → peek → idle) is quicker and eases in, so the panel doesn't linger: cubic-bezier(0.45, 0, 0.2, 1) over 0.34 s.
    static let shellCloseDuration = 0.34
    static let shellCloseCurve = (x1: 0.45, y1: 0.0, x2: 0.2, y2: 1.0)
    /// Outgoing content fades out over this long while the shell shrinks.
    static let fadeOut = 0.15
    /// Leave timer: re-entering cancels it; pinned panels never auto-close.
    static let leaveDelay = 0.35
    /// Content fade-in after the shell moves: opacity 0→1, y -6→0, scale .985→1.
    static let fadeOpen = (duration: 0.35, delay: 0.12)
    static let fadePeekLive = (duration: 0.3, delay: 0.08)
    static let fadeOffsetY: CGFloat = -6
    static let fadeScale: CGFloat = 0.985
    static let popoverFade = 0.22
    /// Main-tab switch: the active pill slides and its label expands over `tabSwitch` (shell curve), screens crossfade over `tabContentFade`.
    static let tabSwitch = 0.3
    static let tabContentFade = 0.18
    /// Live-activity fill: eases toward full over a typical simulator boot (the prototype fakes a 2.4 s one).
    static let liveFillDuration = 25.0

    // MARK: Shell shadow (CSS `0 24px 70px`); `blur` is the CSS blur radius, verify the SwiftUI mapping in the snapshot diff

    static let shadow = (blur: CGFloat(70), y: CGFloat(24), opacity: 0.55, lightOpenOpacity: 0.35)

    // MARK: Open panel chrome

    enum Chrome {
        static let insetX: CGFloat = 20
        static let insetBottom: CGFloat = 16
        static let topRowHeight: CGFloat = 40

        // Main tabs capsule
        static let tabsPadding: CGFloat = 3
        static let tabsGap: CGFloat = 2
        static let tabHeight: CGFloat = 28
        static let tabInactiveMinWidth: CGFloat = 34
        static let tabActivePadding = (leading: CGFloat(10), trailing: CGFloat(12))
        static let tabContentGap: CGFloat = 6
        static let tabIcon: CGFloat = 14

        // Local IP chip + pin / settings buttons
        static let rightClusterGap: CGFloat = 6
        static let iconButton: CGFloat = 30
        static let iconButtonIcon: CGFloat = 14

        // Sub-nav / content / footer vertical rhythm
        static let subNavTop: CGFloat = 14
        static let contentTop: CGFloat = 14
        static let contentTopClaudex: CGFloat = 10
        static let footerTop: CGFloat = 14
        static let footerPaddingTop: CGFloat = 12
        static let footerButtonHeight: CGFloat = 26
        static let footerButtonPaddingX: CGFloat = 10
        static let footerButtonRadius: CGFloat = 8
        static let footerGap: CGFloat = 12

        // Settings popover
        /// Wide enough for the three settings tabs (Appearance, Menus, Clipboard) beside the close button.
        static let popoverWidth: CGFloat = 480 // five sub-tabs + close button
        static let popoverTop: CGFloat = 46
        static let popoverRight: CGFloat = 20
        static let popoverPadding: CGFloat = 14
        static let popoverRadius: CGFloat = 20
        static let popoverGap: CGFloat = 12
        static let popoverShadow = (blur: CGFloat(60), y: CGFloat(24))
    }

    // MARK: Peek ears

    enum Peek {
        static let leftPadding = (leading: CGFloat(16), trailing: CGFloat(12))
        static let leftGap: CGFloat = 8
        static let avatar: CGFloat = 26
        static let nameSize: CGFloat = 13
        static let modeSize: CGFloat = 9.5
        static let modeTracking: CGFloat = 1
        static let modeDot: CGFloat = 5
        static let modeDotGap: CGFloat = 4
        static let textGap: CGFloat = 1

        static let rightPadding = (leading: CGFloat(12), trailing: CGFloat(16))
        static let unitGap: CGFloat = 14
        static let ringToTextGap: CGFloat = 7
        static let ring: CGFloat = 30
        /// Ring drawn in a 36 viewBox: r 15, stroke 4. Scale = ring / 36.
        static let ringViewBox: CGFloat = 36
        static let ringRadius: CGFloat = 15
        static let ringStroke: CGFloat = 4
        static let percentSize: CGFloat = 9
        static let percentTracking: CGFloat = -0.3
        static let labelSize: CGFloat = 9.5
        static let resetSize: CGFloat = 11.5
        /// SF Symbol stand-in for the ↻ glyph; sized to match the reference's small fallback-font glyph.
        static let resetIcon: CGFloat = 10
        /// Glyph before a count (TODO, clips, pinned).
        static let countIcon: CGFloat = 12
        static let countSize: CGFloat = 13
        static let countGap: CGFloat = 4
        static let countPairGap: CGFloat = 9
    }

    // MARK: Live activity

    enum Live {
        static let paddingX: CGFloat = 18
        static let paddingBottom: CGFloat = 12
        static let topRowHeight: CGFloat = 34
        static let iconGap: CGFloat = 7
        static let icon: CGFloat = 14
        static let textSize: CGFloat = 12.5
        static let barHeight: CGFloat = 6
    }
}
