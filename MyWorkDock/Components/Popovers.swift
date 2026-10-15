import SwiftUI

extension Geo {
    enum Appearance {
        static let width = Geo.Chrome.popoverWidth
        static let titleFont: CGFloat = 18
        static let titleTracking: CGFloat = -0.4
        static let closeSize: CGFloat = 28
        static let closeIcon: CGFloat = 11
        static let sectionFont: CGFloat = 11.5
        static let tintNameFont: CGFloat = 12
        static let pullUp: CGFloat = -4 // `margin-top: -4px` on the theme / tint grids
        static let themeGap: CGFloat = 6
        static let themeCardPad = (top: CGFloat(5), side: CGFloat(5), bottom: CGFloat(7))
        static let themeCardRadius: CGFloat = 13
        static let themeCardGap: CGFloat = 6
        static let previewHeight: CGFloat = 52 // inside the 1 pt border
        static let selectedBorder: CGFloat = 2
        static let previewRadius: CGFloat = 8
        static let themeLabelFont: CGFloat = 12
        static let themeIcon: CGFloat = 13
        static let themeIconGap: CGFloat = 5
        static let swatch: CGFloat = 28
        static let swatchGap: CGFloat = 6
        static let swatchCheck: CGFloat = 12
        static let ringWidth: CGFloat = 2
        static let noteFont: CGFloat = 11.5
        /// Five features + Show on all displays: at 36 the popover ran past the 480 pt panel.
        static let menuRowHeight: CGFloat = 32
        static let switchSize = (width: CGFloat(34), height: CGFloat(20))
        static let switchKnob: CGFloat = 14
    }

    enum Menu {
        static let width: CGFloat = 220
        static let padding: CGFloat = 5
        static let radius: CGFloat = 14
        static let rowHeight: CGFloat = 28
        static let rowRadius: CGFloat = 8
        static let rowPadX: CGFloat = 8
        static let rowGap: CGFloat = 8
        static let font: CGFloat = 12.5
        static let checkSlot: CGFloat = 12
        /// Header line box (Chromium: 10.5 pt text, line height normal); the 4 / 6 pt paddings come on top.
        static let headerHeight: CGFloat = 12.5
        static let shadow = (radius: CGFloat(30), y: CGFloat(24))
    }
}

/// Settings: Appearance (theme, tint), Menus (which features are on) and Clipboard (history size). Applies everywhere.
struct SettingsPopover: View {
    enum Page: String { case appearance, menus, clipboard, version }

    var theme: ThemeMode
    /// What macOS is in right now; only shown while `theme == .system`.
    var systemIsDark = true
    var tint: Tint
    var panelSize = PanelSize.medium
    var disabled: Set<Feature> = []
    var allDisplays = false
    var clipboardLimit = ClipboardStore.defaultLimit
    var version = ""
    var updatedAt: Date?
    /// nil in debug builds (no updater): the Version page then says so instead of showing the button.
    var onCheckForUpdates: (() -> Void)?
    var onTheme: (ThemeMode) -> Void = { _ in }
    var onTint: (Tint) -> Void = { _ in }
    var onPanelSize: (PanelSize) -> Void = { _ in }
    var onFeature: (Feature, Bool) -> Void = { _, _ in }
    var onAllDisplays: (Bool) -> Void = { _ in }
    var onClipboardLimit: (Int) -> Void = { _ in }
    var onClose: () -> Void = {}
    @State private var page: Page
    @Environment(\.tokens) private var t

    init(theme: ThemeMode, systemIsDark: Bool = true, tint: Tint, panelSize: PanelSize = .medium, disabled: Set<Feature> = [], allDisplays: Bool = false, page: Page = .appearance,
         clipboardLimit: Int = ClipboardStore.defaultLimit, version: String = "", updatedAt: Date? = nil,
         onCheckForUpdates: (() -> Void)? = nil,
         onTheme: @escaping (ThemeMode) -> Void = { _ in }, onTint: @escaping (Tint) -> Void = { _ in },
         onPanelSize: @escaping (PanelSize) -> Void = { _ in },
         onFeature: @escaping (Feature, Bool) -> Void = { _, _ in }, onAllDisplays: @escaping (Bool) -> Void = { _ in },
         onClipboardLimit: @escaping (Int) -> Void = { _ in }, onClose: @escaping () -> Void = {}) {
        self.theme = theme
        self.systemIsDark = systemIsDark
        self.tint = tint
        self.panelSize = panelSize
        self.disabled = disabled
        self.allDisplays = allDisplays
        self.clipboardLimit = clipboardLimit
        self.version = version
        self.updatedAt = updatedAt
        self.onCheckForUpdates = onCheckForUpdates
        self.onClipboardLimit = onClipboardLimit
        self.onTheme = onTheme
        self.onTint = onTint
        self.onPanelSize = onPanelSize
        self.onFeature = onFeature
        self.onAllDisplays = onAllDisplays
        self.onClose = onClose
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            HStack {
                SubTabs(items: [SubTabItem(Page.appearance.rawValue, "Appearance"), SubTabItem(Page.menus.rawValue, "Menus"),
                                SubTabItem(Page.clipboard.rawValue, "Clipboard"), SubTabItem(Page.version.rawValue, "Version")],
                        selection: page.rawValue, activeFill: t.ctrl) { page = Page(rawValue: $0) ?? .appearance }
                Spacer()
                IconButton(glyph: .close, label: "Close settings", size: Geo.Appearance.closeSize,
                           iconSize: Geo.Appearance.closeIcon, stroke: 2.8, action: onClose)
            }
            switch page {
            case .appearance:
                AppearanceSection(theme: theme, systemIsDark: systemIsDark, tint: tint, panelSize: panelSize,
                                  onTheme: onTheme, onTint: onTint, onPanelSize: onPanelSize)
            case .menus:
                MenusSection(disabled: disabled, allDisplays: allDisplays, onFeature: onFeature, onAllDisplays: onAllDisplays)
            case .clipboard:
                ClipboardSection(limit: clipboardLimit, onLimit: onClipboardLimit)
            case .version:
                VersionSection(version: version, updatedAt: updatedAt, onCheck: onCheckForUpdates)
            }
        }
        .padding(Geo.Chrome.popoverPadding + 1)
        .frame(width: Geo.Appearance.width)
        .background {
            // Shadow on the shape only: on the container every child would cast its own.
            RoundedRectangle(cornerRadius: Geo.Chrome.popoverRadius).fill(t.pop)
                .shadow(color: t.popShadow, radius: Geo.Chrome.popoverShadow.blur / 2, y: Geo.Chrome.popoverShadow.y)
        }
        .overlay(RoundedRectangle(cornerRadius: Geo.Chrome.popoverRadius).strokeBorder(t.border, lineWidth: 1))
    }
}

/// Settings › Version: what is installed, when it arrived, and a manual update check (Sparkle shows its own window).
private struct VersionSection: View {
    var version: String
    var updatedAt: Date?
    var onCheck: (() -> Void)?
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            Text("About").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            VStack(spacing: 0) {
                row("Current version", version)
                row("Last updated", updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            }
            .padding(.top, Geo.Appearance.pullUp)
            if let onCheck {
                DockButton(title: "Check for updates", glyph: .refresh, metrics: .save, tone: .tint, weight: .bold, action: onCheck)
            }
            Text(onCheck == nil ? "Update checks are off in debug builds."
                                : "Updates are checked every hour, downloaded quietly and installed when the dock is idle.")
                .font(Typo.ui(Geo.Appearance.noteFont))
                .foregroundStyle(t.faint)
                .lineSpacing(Typo.lineSpacing(size: Geo.Appearance.noteFont, lineHeight: 1.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typo.ui(Geo.Menu.font, .medium)).foregroundStyle(t.text)
            Spacer(minLength: 0)
            Text(value).font(Typo.mono(Geo.Menu.font)).foregroundStyle(t.text2)
        }
        .padding(.horizontal, Geo.Menu.rowPadX)
        .frame(height: Geo.Appearance.menuRowHeight)
    }
}

/// Settings › Clipboard: how many untagged clips the history keeps. Applied with Enter or Apply, never per keystroke:
/// typing "500" must not pass through "5" and delete clips on the way.
private struct ClipboardSection: View {
    var limit: Int
    var onLimit: (Int) -> Void
    @State private var draft: String
    @Environment(\.tokens) private var t

    init(limit: Int, onLimit: @escaping (Int) -> Void) {
        self.limit = limit
        self.onLimit = onLimit
        _draft = State(initialValue: String(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            Text("History").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            HStack(spacing: Geo.NewTag.gap) {
                Text("Keep the last").font(Typo.ui(Geo.Menu.font, .medium)).foregroundStyle(t.text)
                HStack {
                    DockTextField(text: $draft, placeholder: "\(ClipboardStore.defaultLimit)", font: Typo.mono(Geo.NewTag.font))
                        .frame(height: Geo.NewTag.inputHeight)
                        .onSubmit(apply)
                }
                .padding(.horizontal, Geo.NewTag.fieldPad.leading)
                .frame(width: 64, height: Geo.NewTag.fieldHeight)
                .background(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).fill(t.inset))
                .overlay(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).strokeBorder(t.border, lineWidth: 1))
                Text("clips").font(Typo.ui(Geo.Menu.font, .medium)).foregroundStyle(t.text)
                Spacer(minLength: 0)
                DockButton(title: "Apply", glyph: nil, metrics: .save, tone: .tint, weight: .bold, action: apply)
            }
            .padding(.top, Geo.Appearance.pullUp)
            Text("From 1 to \(ClipboardStore.maxLimit). The limit counts only clips with no tag; tagged and pinned clips are never removed, however many there are.")
                .font(Typo.ui(Geo.Appearance.noteFont))
                .foregroundStyle(t.faint)
                .lineSpacing(Typo.lineSpacing(size: Geo.Appearance.noteFont, lineHeight: 1.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: draft) { draft = String(draft.filter(\.isNumber).prefix(4)) }
        .onChange(of: limit) { draft = String(limit) }
    }

    /// Blank or non-numeric input goes back to the current limit.
    private func apply() {
        let n = ClipboardStore.clamp(Int(draft) ?? limit)
        draft = String(n)
        onLimit(n)
    }
}

/// Settings › Menus: one switch per feature. Off hides it and stops its background work.
private struct MenusSection: View {
    var disabled: Set<Feature>
    var allDisplays: Bool
    var onFeature: (Feature, Bool) -> Void
    var onAllDisplays: (Bool) -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            Text("Menus").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            VStack(spacing: 0) {
                ForEach(Feature.allCases) { row($0) }
            }
            .padding(.top, Geo.Appearance.pullUp)
            Text("A menu that is switched off is hidden and stops everything it runs in the background.")
                .font(Typo.ui(Geo.Appearance.noteFont))
                .foregroundStyle(t.faint)
                .lineSpacing(Typo.lineSpacing(size: Geo.Appearance.noteFont, lineHeight: 1.4))
                .fixedSize(horizontal: false, vertical: true)
            Text("Displays").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            row("Show on all displays", .monitor, on: allDisplays) { onAllDisplays(!allDisplays) }
                .padding(.top, Geo.Appearance.pullUp)
            Text("Also draws the notch on every other display. Hover or click one to use it there.")
                .font(Typo.ui(Geo.Appearance.noteFont))
                .foregroundStyle(t.faint)
                .lineSpacing(Typo.lineSpacing(size: Geo.Appearance.noteFont, lineHeight: 1.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ feature: Feature) -> some View {
        row(feature.label, feature.glyph, on: !disabled.contains(feature)) { onFeature(feature, disabled.contains(feature)) }
    }

    private func row(_ label: String, _ glyph: Glyph, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: Geo.Menu.rowGap) {
                Icon(glyph, size: Geo.Appearance.themeIcon).foregroundStyle(on ? t.text : t.muted)
                Text(label).font(Typo.ui(Geo.Menu.font, .medium)).foregroundStyle(on ? t.text : t.text2)
                Spacer(minLength: 0)
                SwitchPill(on: on)
            }
            .padding(.horizontal, Geo.Menu.rowPadX)
            .frame(height: Geo.Appearance.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// Drawn by hand: the system `Toggle` is AppKit-backed, which `ImageRenderer` snapshots cannot draw.
struct SwitchPill: View {
    var on: Bool
    @Environment(\.tokens) private var t

    var body: some View {
        let size = Geo.Appearance.switchSize
        let inset = (size.height - Geo.Appearance.switchKnob) / 2
        Capsule().fill(on ? t.accent : t.ctrl)
            .overlay(Capsule().strokeBorder(on ? .clear : t.border, lineWidth: 1))
            .overlay(alignment: .leading) {
                Circle().fill(on ? Tokens.onTint : t.muted)
                    .frame(width: Geo.Appearance.switchKnob, height: Geo.Appearance.switchKnob)
                    .offset(x: on ? size.width - Geo.Appearance.switchKnob - inset : inset)
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeOut(duration: 0.15), value: on)
    }
}

/// Theme cards with miniatures, 8 tint swatches.
private struct AppearanceSection: View {
    var theme: ThemeMode
    var systemIsDark = true
    var tint: Tint
    var panelSize = PanelSize.medium
    var onTheme: (ThemeMode) -> Void = { _ in }
    var onTint: (Tint) -> Void = { _ in }
    var onPanelSize: (PanelSize) -> Void = { _ in }
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            Text("Theme").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
            HStack(spacing: Geo.Appearance.themeGap) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    themeCard(mode)
                }
            }
            .padding(.top, Geo.Appearance.pullUp)
            if theme == .system {
                Text("Following macOS · currently \(systemIsDark ? "Dark" : "Light")")
                    .font(Typo.ui(Geo.Appearance.noteFont))
                    .foregroundStyle(t.faint)
                    .padding(.top, Geo.Appearance.pullUp)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Tint").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
                Spacer()
                Text(tint.name).font(Typo.ui(Geo.Appearance.tintNameFont, .semibold)).foregroundStyle(t.text2)
            }
            HStack(spacing: Geo.Appearance.swatchGap + 0.5) { // 8 equal grid cells of 28.5 pt, 28 pt swatches
                ForEach(Tint.allCases) { swatch($0) }
            }
            .padding(.top, Geo.Appearance.pullUp)

            Text("Applies to the peek, the panel and live activities.")
                .font(Typo.ui(Geo.Appearance.noteFont))
                .foregroundStyle(t.faint)
                .lineSpacing(Typo.lineSpacing(size: Geo.Appearance.noteFont, lineHeight: 1.4))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Panel size").font(Typo.ui(Geo.Appearance.sectionFont, .semibold)).foregroundStyle(t.faint)
                Spacer()
                SubTabs(items: PanelSize.allCases.map { SubTabItem($0.rawValue, $0.label) },
                        selection: panelSize.rawValue, activeFill: t.ctrl) { onPanelSize(PanelSize(rawValue: $0) ?? .medium) }
            }
        }
    }

    private func themeCard(_ mode: ThemeMode) -> some View {
        let on = theme == mode
        let preview = Fixed.themePreview(mode)
        return Button { onTheme(mode) } label: {
            VStack(alignment: .leading, spacing: Geo.Appearance.themeCardGap) {
                miniature(preview)

                HStack(spacing: Geo.Appearance.themeIconGap) {
                    Icon(mode == .system ? .monitor : mode == .dark ? .moon : .sun, size: Geo.Appearance.themeIcon)
                    Text(mode == .system ? "System" : mode == .dark ? "Dark" : "Light")
                }
                .font(Typo.ui(Geo.Appearance.themeLabelFont, .semibold))
                .padding(.leading, 2)
            }
            .foregroundStyle(t.text)
            .padding(.top, Geo.Appearance.themeCardPad.top)
            .padding(.horizontal, Geo.Appearance.themeCardPad.side)
            .padding(.bottom, Geo.Appearance.themeCardPad.bottom)
            // Border-box buttons in a stretched grid: content sits inside the 2 pt (selected) or 1 pt border, and the
            // unselected cards take the difference at the bottom so all three are equally tall.
            .padding(.top, on ? Geo.Appearance.selectedBorder : 1)
            .padding(.horizontal, on ? Geo.Appearance.selectedBorder : 1)
            .padding(.bottom, 2 * Geo.Appearance.selectedBorder - (on ? Geo.Appearance.selectedBorder : 1))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Geo.Appearance.themeCardRadius)
                .strokeBorder(on ? t.text : t.border, lineWidth: on ? Geo.Appearance.selectedBorder : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .system ? "System" : mode == .dark ? "Dark" : "Light")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Mini window: hardware notch, accent pill and two text bars, positioned like the markup
    /// (children are absolutely positioned inside the 1 pt border, 52 pt tall).
    private func miniature(_ p: (fill: AnyShapeStyle, line: Color, bar: Color)) -> some View {
        let r = Geo.Appearance.previewRadius
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5).fill(Fixed.shell)
                    .frame(width: 36, height: 8)
                    .offset(x: (geo.size.width - 36) / 2)
                Capsule().fill(t.accent).frame(width: 24, height: 7).offset(x: 7, y: 13)
                Capsule().fill(p.bar).frame(width: geo.size.width - 14, height: 5).offset(x: 7, y: 25)
                Capsule().fill(p.bar).frame(width: geo.size.width * 0.6, height: 5).offset(x: 7, y: 35)
            }
        }
        .frame(height: Geo.Appearance.previewHeight)
        .background(p.fill)
        .clipShape(RoundedRectangle(cornerRadius: r - 1))
        .padding(1)
        .background(RoundedRectangle(cornerRadius: r).fill(p.fill))
        .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(p.line, lineWidth: 1))
    }

    private func swatch(_ s: Tint) -> some View {
        let on = s == tint
        return Button { onTint(s) } label: {
            Circle().fill(s.color)
                .frame(width: Geo.Appearance.swatch, height: Geo.Appearance.swatch)
                .overlay { if on { Icon(.check, size: Geo.Appearance.swatchCheck, stroke: 3.4).foregroundStyle(Tokens.onTint) } }
                .overlay {
                    if !on { Circle().strokeBorder(Fixed.swatchLine, lineWidth: 1) }
                }
                .background {
                    // box-shadow: 0 0 0 2px pop, 0 0 0 4px tint
                    if on {
                        Circle().fill(s.color).padding(-2 * Geo.Appearance.ringWidth)
                        Circle().fill(t.pop).padding(-Geo.Appearance.ringWidth)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Dropdown list in a popover surface (claudex sort menu): checkmark slot, selected row on `ctrl`.
struct MenuPopover: View {
    var options: [String]
    var selected: Int
    var onSelect: (Int) -> Void = { _ in }
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button { onSelect(i) } label: {
                    HStack(spacing: Geo.Menu.rowGap) {
                        // Always laid out (hidden when unselected): an empty view would collapse the 12 pt slot.
                        Icon(.check, size: 12, stroke: 3)
                            .opacity(i == selected ? 1 : 0)
                            .frame(width: Geo.Menu.checkSlot, alignment: .leading)
                        Text(options[i])
                        Spacer(minLength: 0)
                    }
                    .font(Typo.ui(Geo.Menu.font, .medium))
                    .foregroundStyle(t.text)
                    .padding(.horizontal, Geo.Menu.rowPadX)
                    .frame(height: Geo.Menu.rowHeight)
                    .background(RoundedRectangle(cornerRadius: Geo.Menu.rowRadius).fill(i == selected ? t.ctrl : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Geo.Menu.padding + 1)
        .frame(width: Geo.Menu.width)
        .background {
            RoundedRectangle(cornerRadius: Geo.Menu.radius).fill(t.pop)
                .shadow(color: t.popShadow, radius: Geo.Menu.shadow.radius, y: Geo.Menu.shadow.y)
        }
        .overlay(RoundedRectangle(cornerRadius: Geo.Menu.radius).strokeBorder(t.border, lineWidth: 1))
    }
}

struct TagMenuOption: Identifiable {
    var id: String
    var label: String
    /// nil draws the hollow ring ("No tag", "All") instead of a colour dot.
    var dot: Color?
    var count: Int?
    /// Shows edit / delete buttons (user tags).
    var editable = false
}

/// Edit / delete hooks for the editable rows of a `TagMenu`.
struct TagMenuEditing {
    var onEdit: (String) -> Void
    var onDelete: (String) -> Void
}

/// Tag dropdown (assign tag, filter by tag): small-caps header, rows with dot, label, optional count and a ✓ slot,
/// then an optional footer (the `New tag` field).
struct TagMenu<Footer: View>: View {
    var title: String
    var options: [TagMenuOption]
    var selected: String
    var width: CGFloat
    var onSelect: (String) -> Void
    var edit: TagMenuEditing?
    /// Rows beyond this many scroll, so the menu never outgrows the panel.
    var maxRows: Int?
    @ViewBuilder var footer: Footer
    @Environment(\.tokens) private var t

    init(title: String, options: [TagMenuOption], selected: String, width: CGFloat,
         onSelect: @escaping (String) -> Void = { _ in }, edit: TagMenuEditing? = nil, maxRows: Int? = nil,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.options = options
        self.selected = selected
        self.width = width
        self.onSelect = onSelect
        self.edit = edit
        self.maxRows = maxRows
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            TagMenuHeader(title: title)
            let rows = VStack(spacing: 0) {
                ForEach(options) { o in
                    TagMenuRow(option: o, selected: o.id == selected, edit: edit) { onSelect(o.id) }
                }
            }
            if let maxRows, options.count > maxRows {
                DockScroll { rows }.frame(height: CGFloat(maxRows) * Geo.Menu.rowHeight)
            } else {
                rows
            }
            footer
        }
        .tagMenuSurface(width: width)
    }
}

/// Small-caps header line of a tag menu / form.
private struct TagMenuHeader: View {
    var title: String
    @Environment(\.tokens) private var t

    var body: some View {
        Text(title)
            .font(Typo.ui(10.5, .bold)).tracking(1).foregroundStyle(t.faint)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Geo.Menu.headerHeight, maxHeight: Geo.Menu.headerHeight, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 6)
    }
}

private extension View {
    /// Popover surface shared by `TagMenu` and `TagFormPopover`.
    func tagMenuSurface(width: CGFloat) -> some View { modifier(TagMenuSurface(width: width)) }
}

private struct TagMenuSurface: ViewModifier {
    var width: CGFloat
    @Environment(\.tokens) private var t

    func body(content: Content) -> some View {
        content
            .padding(Geo.Menu.padding + 1)
            .frame(width: width)
            .background {
                RoundedRectangle(cornerRadius: Geo.Menu.radius).fill(t.pop)
                    .shadow(color: t.popShadow, radius: Geo.Menu.shadow.radius, y: Geo.Menu.shadow.y)
            }
            .overlay(RoundedRectangle(cornerRadius: Geo.Menu.radius).strokeBorder(t.border, lineWidth: 1))
    }
}

extension TagMenu where Footer == EmptyView {
    init(title: String, options: [TagMenuOption], selected: String, width: CGFloat, onSelect: @escaping (String) -> Void = { _ in }) {
        self.init(title: title, options: options, selected: selected, width: width, onSelect: onSelect) { EmptyView() }
    }
}

/// One `TagMenu` row. Editable rows always show pencil / trash between the label and the ✓ slot.
private struct TagMenuRow: View {
    var option: TagMenuOption
    var selected: Bool
    var edit: TagMenuEditing?
    var onSelect: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Geo.Menu.rowGap) {
                Circle().fill(option.dot ?? .clear)
                    .overlay { if option.dot == nil { Circle().strokeBorder(t.muted, lineWidth: 1.5) } }
                    .frame(width: 8, height: 8)
                Text(option.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    if let count = option.count { Text("\(count)").font(Typo.ui(11)).foregroundStyle(t.faint) }
                    if option.editable, edit != nil { Color.clear.frame(width: 2 * Geo.TagTool.size, height: 1) } // room for the buttons below
                }
                Icon(.check, size: 12, stroke: 3)
                    .opacity(selected ? 1 : 0)
                    .frame(width: Geo.Menu.checkSlot)
            }
            .font(Typo.ui(Geo.Menu.font, .medium))
            .foregroundStyle(t.text)
            .padding(.horizontal, Geo.Menu.rowPadX)
            .frame(height: Geo.Menu.rowHeight)
            .background(RoundedRectangle(cornerRadius: Geo.Menu.rowRadius).fill(selected ? t.ctrl : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if option.editable, let edit {
                HStack(spacing: 0) {
                    tool(.pencil, "Edit tag \(option.label)", t.muted) { edit.onEdit(option.id) }
                    tool(.trash, "Delete tag \(option.label)", t.red) { edit.onDelete(option.id) }
                }
                .padding(.trailing, Geo.Menu.rowPadX + Geo.Menu.checkSlot + Geo.Menu.rowGap)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tool(_ glyph: Glyph, _ label: String, _ fg: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(glyph, size: 12).foregroundStyle(fg)
                .frame(width: Geo.TagTool.size, height: Geo.TagTool.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension Geo {
    enum NewTag {
        static let marginTop: CGFloat = 5
        static let padTop: CGFloat = 6
        static let fieldHeight: CGFloat = 30
        static let fieldRadius: CGFloat = 8
        static let fieldPad = (leading: CGFloat(8), trailing: CGFloat(8))
        static let gap: CGFloat = 6
        static let font: CGFloat = 12.5
        static let inputHeight: CGFloat = 24
        static let buttonHeight: CGFloat = 26
        static let buttonPadX: CGFloat = 12
        static let buttonRadius: CGFloat = 7
        static let buttonFont: CGFloat = 12
        static let swatch: CGFloat = 22
        static let formGap: CGFloat = 12
        static let formPad: CGFloat = 4 // inside the menu padding, so the form lines up with the rows' text
    }

    /// Pencil / trash button in an editable tag row.
    enum TagTool {
        static let size: CGFloat = 22
    }
}

/// Footer of the tag menus: divider, then `＋ New tag` (opens the `TagFormPopover`) and, at the right, an optional second
/// action (`✎ Manage` in the pickers, `✓ Done` in the manage list).
struct NewTagButton: View {
    var action: () -> Void
    var trailing: (title: String, glyph: Glyph, action: () -> Void)?
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            row("New tag", .plus, action).frame(maxWidth: .infinity, alignment: .leading)
            if let trailing { row(trailing.title, trailing.glyph, trailing.action) }
        }
        .padding(.top, Geo.NewTag.padTop)
        .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
        .padding(.top, Geo.NewTag.marginTop)
    }

    private func row(_ title: String, _ glyph: Glyph, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Geo.Menu.rowGap) {
                Icon(glyph, size: 11, stroke: 2.8)
                Text(title)
            }
            .font(Typo.ui(Geo.Menu.font, .medium))
            .foregroundStyle(t.text2)
            .padding(.horizontal, Geo.Menu.rowPadX)
            .frame(height: Geo.Menu.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Name + colour popup that takes the place of a tag menu's list (new tag and edit tag): `# name` field, one swatch per
/// palette colour, Cancel / Add (Save while editing). Enter saves, Esc cancels.
struct TagFormPopover: View {
    @Binding var name: String
    @Binding var hex: UInt32
    var editing: Bool
    var canSave: Bool
    var width: CGFloat
    var onSave: () -> Void
    var onCancel: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.NewTag.formGap) {
            TagMenuHeader(title: editing ? "EDIT TAG" : "NEW TAG")
            field
            HStack(spacing: 0) {
                ForEach(NotesStore.tagPalette, id: \.self) { swatch($0) }
            }
            .padding(.horizontal, Geo.NewTag.formPad)
            HStack(spacing: Geo.NewTag.gap) {
                Spacer(minLength: 0)
                button("Cancel", fg: t.text2, bg: t.btn2, action: onCancel)
                button(editing ? "Save" : "Add", fg: canSave ? Tokens.onTint : t.offFg, bg: canSave ? t.accent : t.btnOff, action: onSave)
                    .disabled(!canSave)
            }
            .padding(.horizontal, Geo.NewTag.formPad)
        }
        .padding(.bottom, Geo.NewTag.formPad)
        .tagMenuSurface(width: width)
    }

    private var field: some View {
        HStack(spacing: Geo.NewTag.gap) {
            Text("#").font(Typo.ui(Geo.NewTag.font, .bold)).foregroundStyle(t.faint)
            DockTextField(text: $name, placeholder: "Tag name", font: Typo.ui(Geo.NewTag.font), autofocus: true)
                .frame(height: Geo.NewTag.inputHeight)
                .onSubmit { if canSave { onSave() } }
                .onKeyPress(.escape) { onCancel(); return .handled }
        }
        .padding(.horizontal, Geo.NewTag.fieldPad.leading)
        .frame(height: Geo.NewTag.fieldHeight)
        .background(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).fill(t.inset))
        .overlay(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).strokeBorder(t.border, lineWidth: 1))
        .padding(.horizontal, Geo.NewTag.formPad)
    }

    private func swatch(_ color: UInt32) -> some View {
        let on = color == hex
        return Button { hex = color } label: {
            Circle().fill(Color(hex: color))
                .frame(width: Geo.NewTag.swatch, height: Geo.NewTag.swatch)
                .overlay { if on { Icon(.check, size: 11, stroke: 3.4).foregroundStyle(Tokens.onTint) } }
                .background { // box-shadow: 0 0 0 2px pop, 0 0 0 4px colour, like the tint swatches
                    if on {
                        Circle().fill(Color(hex: color)).padding(-2 * Geo.Appearance.ringWidth)
                        Circle().fill(t.pop).padding(-Geo.Appearance.ringWidth)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour #\(String(color, radix: 16))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func button(_ title: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.ui(Geo.NewTag.buttonFont, .bold))
                .foregroundStyle(fg)
                .padding(.horizontal, Geo.NewTag.buttonPadX)
                .frame(height: Geo.NewTag.buttonHeight)
                .background(RoundedRectangle(cornerRadius: Geo.NewTag.buttonRadius).fill(bg))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Inverted pill so it reads on both themes.
struct HintToast: View {
    var text: String
    @Environment(\.tokens) private var t

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 7) {
            Icon(.copy, size: 12)
            Text(text).font(Typo.ui(12.5, .semibold))
        }
        .foregroundStyle(t.panel)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(t.text))
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}
