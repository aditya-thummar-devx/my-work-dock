import SwiftUI

/// What Settings needs of the custom buddies: the library, and the two things the user can do to it.
struct CustomBuddies {
    /// nil where nothing is saved (previews, snapshots that do not show the library).
    var library: CustomBuddyStore?
    var add: () -> Void = {}
    var remove: (String) -> Void = { _ in }
    /// Picks the file for one state of a buddy.
    var setFile: (BuddyState, String) -> Void = { _, _ in }
}

/// Settings › Appearance › Notch buddy (design/Buddy-Settings.dc.html): the switch, then style, emoji, motion and full-screen
/// choices, all dimmed and locked while the buddy is off. Every change applies at once, the notch is the preview.
struct BuddySettings: View {
    var prefs: BuddyPrefs
    var customs = CustomBuddies()
    var onChange: (BuddyPrefs) -> Void = { _ in }
    @Environment(\.tokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The brief is on the clipboard (the button says so for a moment).
    @State private var copied = false

    private var library: CustomBuddyStore { customs.library ?? .sample() }

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
                if prefs.style == .custom { customSection }
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
                    case .custom:
                        if let entry = library.entry(prefs.custom) {
                            BuddyStillView(asset: .custom(entry), tint: t.buddy, fit: CGSize(width: Geo.Buddy.stylePreviewHeight, height: Geo.Buddy.stylePreviewHeight - 8))
                        } else {
                            Icon(.plus, size: 16).foregroundStyle(t.faint)
                        }
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

    // MARK: Custom buddies

    /// The buddies the user added, a + to add one, what a file has to be, and how to make one.
    private var customSection: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Geo.Buddy.emojiTile), spacing: Geo.Appearance.themeGap)], alignment: .leading,
                      spacing: Geo.Appearance.themeGap) {
                ForEach(library.entries) { customTile($0) }
                addTile(full: library.entries.count >= BuddyFileCheck.Limits.library)
            }
            if let entry = library.entry(prefs.custom) {
                HStack {
                    Text(entry.id).font(Typo.ui(Geo.Appearance.tintNameFont, .semibold)).foregroundStyle(t.text2).lineLimit(1)
                    Spacer()
                    Button { customs.remove(entry.id) } label: {
                        Text("Remove").font(Typo.ui(Geo.Appearance.noteFont, .semibold)).foregroundStyle(t.red)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(BuddyState.allCases) { stateRow($0, of: entry) }
            }
            if !library.rejection.isEmpty { rejection(library.rejection) }
            note(BuddyFileCheck.Limits.summary)
            howTo
        }
    }

    private func customTile(_ entry: CustomBuddyStore.Entry) -> some View {
        let on = prefs.custom == entry.id
        return Button { change { $0.custom = entry.id } } label: {
            BuddyStillView(asset: .custom(entry), tint: t.buddy, fit: CGSize(width: Geo.Buddy.emojiTile, height: Geo.Buddy.emojiTile))
                .scaleEffect(0.75)
                .frame(width: Geo.Buddy.emojiTile, height: Geo.Buddy.emojiTile)
                .background(RoundedRectangle(cornerRadius: Geo.Buddy.emojiTileRadius).fill(on ? t.subOn : t.list))
                .overlay { if on { RoundedRectangle(cornerRadius: Geo.Buddy.emojiTileRadius).strokeBorder(t.ink, lineWidth: Geo.Appearance.selectedBorder) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Remove \(entry.id)") { customs.remove(entry.id) } }
        .help(entry.id)
        .accessibilityLabel(entry.id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// One state of the chosen buddy: its file (idle always has one) and where it sits, in points from the ear's centre.
    private func stateRow(_ state: BuddyState, of entry: CustomBuddyStore.Entry) -> some View {
        let has = entry.files[state] != nil
        return VStack(alignment: .leading, spacing: Geo.Buddy.States.rowGap) {
            HStack(spacing: Geo.Menu.rowGap) {
                ZStack {
                    RoundedRectangle(cornerRadius: Geo.Buddy.emojiTileRadius).fill(t.panel)
                    if has {
                        BuddyStillView(asset: .custom(entry, state), tint: t.buddy, fit: CGSize(width: Geo.Buddy.emojiTile - 6, height: Geo.Buddy.emojiTile - 6))
                    } else {
                        Text("None").font(Typo.ui(Geo.Appearance.noteFont)).foregroundStyle(t.faint)
                    }
                }
                .frame(width: Geo.Buddy.emojiTile, height: Geo.Buddy.emojiTile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.label).font(Typo.ui(Geo.Menu.font, .medium)).foregroundStyle(t.text)
                    Text(has || state == .idle ? state.caption : "Skipped: no file.").font(Typo.ui(Geo.Appearance.noteFont)).foregroundStyle(t.faint)
                }
                Spacer(minLength: 0)
                Button { customs.setFile(state, entry.id) } label: {
                    Text(has ? "Replace" : "Add").font(Typo.ui(Geo.Appearance.noteFont, .semibold)).foregroundStyle(t.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(has ? "Replace" : "Add") the \(state.label) file")
                if has, state != .idle {
                    Button { library.removeFile(state, of: entry.id) } label: {
                        Text("Remove").font(Typo.ui(Geo.Appearance.noteFont, .semibold)).foregroundStyle(t.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove the \(state.label) file")
                }
            }
            if has {
                OffsetEditor(value: entry.offsets[state]) { library.setOffset(state, of: entry.id, to: $0) }
            }
        }
        .padding(Geo.Menu.rowPadX)
        .modifier(MenuCard())
        .id("\(entry.id) \(state.rawValue)") // a new buddy's fields start from its own numbers
    }

    private func addTile(full: Bool) -> some View {
        Button(action: customs.add) {
            Icon(.plus, size: 16)
                .foregroundStyle(t.muted)
                .frame(width: Geo.Buddy.emojiTile, height: Geo.Buddy.emojiTile)
                .overlay(RoundedRectangle(cornerRadius: Geo.Buddy.emojiTileRadius).strokeBorder(t.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? Geo.Buddy.dimmed : 1)
        .help(full ? "The library is full (\(BuddyFileCheck.Limits.library)). Remove a buddy first." : "Add a Lottie file")
        .accessibilityLabel("Add a custom buddy")
    }

    /// Why the last file was turned down, the first few reasons.
    private func rejection(_ reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("That file can't be used:").fontWeight(.semibold)
            ForEach(Array(reasons.prefix(3).enumerated()), id: \.offset) { _, reason in Text("• \(reason)") }
            if reasons.count > 3 { Text("…and \(reasons.count - 3) more") }
        }
        .font(Typo.ui(Geo.Appearance.noteFont))
        .foregroundStyle(t.red)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to make one").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            ForEach(Array(BuddyBrief.steps.enumerated()), id: \.offset) { n, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(n + 1).").font(Typo.mono(Geo.Appearance.noteFont)).foregroundStyle(t.faint)
                    Text(step).font(Typo.ui(Geo.Appearance.noteFont)).foregroundStyle(t.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            PillButton(title: copied ? "Copied" : "Copy design brief", glyph: copied ? .check : .copy, iconSize: 13) {
                Clipboard.copy(BuddyBrief.text)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    copied = false
                }
            }
            .padding(.top, 2)
        }
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

/// A state's X and Y offset in points, any whole number (negative: left / up). Typed in and applied together, like the clipboard limit:
/// writing the store on every key would redraw the panel under the cursor and drop the field's focus.
struct OffsetEditor: View {
    var value: CGPoint
    var onApply: (CGPoint) -> Void
    @State private var x: String
    @State private var y: String
    @Environment(\.tokens) private var t

    init(value: CGPoint, onApply: @escaping (CGPoint) -> Void) {
        self.value = value
        self.onApply = onApply
        _x = State(initialValue: String(Int(value.x)))
        _y = State(initialValue: String(Int(value.y)))
    }

    var body: some View {
        HStack(spacing: Geo.Menu.rowGap) {
            Text("Offset").font(Typo.ui(Geo.Appearance.noteFont)).foregroundStyle(t.faint)
            field("X", $x)
            field("Y", $y)
            Spacer(minLength: 0)
            DockButton(title: "Apply", glyph: nil, metrics: .save, tone: .tint, weight: .bold, action: apply)
        }
        .onChange(of: x) { x = Self.clean(x) }
        .onChange(of: y) { y = Self.clean(y) }
        .onChange(of: value) { // changed elsewhere: show it
            x = String(Int(value.x))
            y = String(Int(value.y))
        }
    }

    private func field(_ axis: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(axis).font(Typo.ui(Geo.Appearance.noteFont, .semibold)).foregroundStyle(t.text2)
            HStack {
                DockTextField(text: text, placeholder: "0", font: Typo.mono(Geo.NewTag.font))
                    .frame(height: Geo.NewTag.inputHeight)
                    .onSubmit(apply)
            }
            .padding(.horizontal, Geo.NewTag.fieldPad.leading)
            .frame(width: 64, height: Geo.NewTag.fieldHeight)
            .background(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).fill(t.inset))
            .overlay(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).strokeBorder(t.border, lineWidth: 1))
            .accessibilityLabel("\(axis) offset in points")
        }
    }

    /// An optional minus, then up to five digits.
    static func clean(_ text: String) -> String {
        (text.hasPrefix("-") ? "-" : "") + String(text.filter(\.isNumber).prefix(5))
    }

    /// Blank or just a minus keeps the number that was there.
    private func apply() {
        let point = CGPoint(x: Int(x) ?? Int(value.x), y: Int(y) ?? Int(value.y))
        x = String(Int(point.x))
        y = String(Int(point.y))
        onApply(point)
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
