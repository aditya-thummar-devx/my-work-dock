import SwiftUI

/// Settings › Appearance › Notch buddy (design/Buddy-Settings.dc.html): the switch, then style, emoji, motion and full-screen
/// choices, all dimmed and locked while the buddy is off. Every change applies at once, the notch is the preview.
struct BuddySettings: View {
    var prefs: BuddyPrefs
    var onChange: (BuddyPrefs) -> Void = { _ in }
    @Environment(\.tokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func change(_ edit: (inout BuddyPrefs) -> Void) {
        var next = prefs
        edit(&next)
        onChange(next)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            Text("Notch buddy").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            mainSwitch
            VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
                Text("Style").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
                HStack(spacing: Geo.Appearance.themeGap) {
                    ForEach(BuddyStyle.allCases) { styleCard($0) }
                }
                .padding(.top, Geo.Appearance.pullUp)
                if prefs.style == .emoji {
                    HStack(spacing: Geo.Appearance.themeGap) {
                        ForEach(BuddyEmoji.allCases) { emojiTile($0) }
                    }
                }
                HStack {
                    Text("Motion").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
                    Spacer()
                    SubTabs(items: BuddyMotion.allCases.map { SubTabItem($0.rawValue, $0.label) },
                            selection: prefs.motion.rawValue) { id in change { $0.motion = BuddyMotion(rawValue: id) ?? .lively } }
                }
                if reduceMotion {
                    note("Reduce Motion is on in macOS, so the buddy stays still.")
                }
                SwitchRow(label: "Hide in full-screen apps", glyph: nil, on: prefs.hideInFullScreen) { change { $0.hideInFullScreen.toggle() } }
                    .modifier(MenuCard())
            }
            .opacity(prefs.on ? 1 : Geo.Buddy.dimmed)
            .disabled(!prefs.on)
            (Text("Off: the notch looks like plain hardware. Hover and ")
                + Text("⌥Space").font(Typo.mono(Geo.Appearance.noteFont)).foregroundColor(t.text2)
                + Text(" still open it."))
                .font(Typo.ui(Geo.Appearance.noteFont))
                .foregroundStyle(t.faint)
                .lineSpacing(Typo.lineSpacing(size: Geo.Appearance.noteFont, lineHeight: 1.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typo.ui(Geo.Appearance.noteFont))
            .foregroundStyle(t.faint)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Show notch buddy" with its caption: a card of its own, so the choices below read as belonging to it.
    private var mainSwitch: some View {
        Button { change { $0.on.toggle() } } label: {
            HStack(spacing: Geo.Menu.rowGap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show notch buddy").font(Typo.ui(Geo.Menu.font, .medium)).foregroundStyle(prefs.on ? t.text : t.text2)
                    Text("An animated icon beside the notch so you can tell the app is running.")
                        .font(Typo.ui(Geo.Appearance.noteFont))
                        .foregroundStyle(t.faint)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SwitchPill(on: prefs.on)
            }
            .padding(.horizontal, Geo.Menu.rowPadX)
            .padding(.vertical, Geo.Menu.rowPadX)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(MenuCard())
        .accessibilityLabel("Show notch buddy")
        .accessibilityValue(prefs.on ? "On" : "Off")
    }

    /// A miniature of the notch ear (the shell's own colour, so black in the dark theme and light in the light one) with the style in
    /// it, like the theme cards. The chosen one is ringed in the ink colour (the tint is unreadable on the light panel).
    private func styleCard(_ style: BuddyStyle) -> some View {
        let on = prefs.style == style
        let pad = Geo.Buddy.styleCardPad
        return Button { change { $0.style = style } } label: {
            VStack(spacing: Geo.Appearance.themeCardGap) {
                ZStack {
                    RoundedRectangle(cornerRadius: Geo.Buddy.stylePreviewRadius).fill(t.panel)
                    switch style {
                    case .face:
                        StyleFace(accent: t.buddy)
                    case .pulse:
                        Circle().fill(t.buddy).frame(width: Geo.Buddy.dot, height: Geo.Buddy.dot)
                            .background(Circle().fill(t.text.opacity(0.12)).padding(-3))
                    case .emoji:
                        Text(prefs.emoji.glyph).font(.system(size: Geo.Buddy.emoji))
                    }
                }
                .frame(height: Geo.Buddy.stylePreviewHeight)
                Text(style.label).font(Typo.ui(Geo.Appearance.themeLabelFont, .semibold))
            }
            .foregroundStyle(t.text)
            .padding(.top, pad.top).padding(.horizontal, pad.side).padding(.bottom, pad.bottom)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Geo.Buddy.styleCardRadius)
                .strokeBorder(on ? t.ink : t.border, lineWidth: on ? Geo.Appearance.selectedBorder : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func emojiTile(_ emoji: BuddyEmoji) -> some View {
        let on = prefs.emoji == emoji
        return Button { change { $0.emoji = emoji } } label: {
            Text(emoji.glyph).font(.system(size: Geo.Buddy.emojiTileFont))
                .frame(width: Geo.Buddy.emojiTile, height: Geo.Buddy.emojiTile)
                .background(RoundedRectangle(cornerRadius: Geo.Buddy.emojiTileRadius).fill(on ? t.subOn : t.list))
                .overlay { if on { RoundedRectangle(cornerRadius: Geo.Buddy.emojiTileRadius).strokeBorder(t.ink, lineWidth: Geo.Appearance.selectedBorder) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(emoji.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The face card's miniature, drawn as the design does (a 16 pt face with smaller eyes). The live face is the Lottie file.
private struct StyleFace: View {
    var accent: Color

    var body: some View {
        Circle().fill(accent)
            .frame(width: Geo.Buddy.styleFace, height: Geo.Buddy.styleFace)
            .overlay {
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Geo.Buddy.eyeRadius).fill(Tokens.onTint).frame(width: 2.5, height: 4.5)
                    }
                }
                .offset(y: -Geo.Buddy.eyeRaise)
            }
    }
}
