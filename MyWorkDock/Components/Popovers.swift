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

/// Settings › Appearance: theme cards with miniatures, 8 tint swatches. Applies everywhere.
struct AppearancePopover: View {
    var theme: ThemeMode
    /// What macOS is in right now; only shown while `theme == .system`.
    var systemIsDark = true
    var tint: Tint
    var onTheme: (ThemeMode) -> Void = { _ in }
    var onTint: (Tint) -> Void = { _ in }
    var onClose: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: Geo.Chrome.popoverGap) {
            HStack {
                Text("Appearance").font(Typo.display(Geo.Appearance.titleFont)).tracking(Geo.Appearance.titleTracking)
                Spacer()
                IconButton(glyph: .close, label: "Close settings", size: Geo.Appearance.closeSize,
                           iconSize: Geo.Appearance.closeIcon, stroke: 2.8, action: onClose)
            }

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
}

/// Tag dropdown (assign tag, filter by tag): small-caps header, rows with dot, label, optional count and a ✓ slot,
/// then an optional footer (the `New tag` field).
struct TagMenu<Footer: View>: View {
    var title: String
    var options: [TagMenuOption]
    var selected: String
    var width: CGFloat
    var onSelect: (String) -> Void
    @ViewBuilder var footer: Footer
    @Environment(\.tokens) private var t

    init(title: String, options: [TagMenuOption], selected: String, width: CGFloat,
         onSelect: @escaping (String) -> Void = { _ in }, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.options = options
        self.selected = selected
        self.width = width
        self.onSelect = onSelect
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Typo.ui(10.5, .bold)).tracking(1).foregroundStyle(t.faint)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Geo.Menu.headerHeight, maxHeight: Geo.Menu.headerHeight, alignment: .leading)
                .padding(.top, 4).padding(.bottom, 6)
            ForEach(options) { o in
                Button { onSelect(o.id) } label: {
                    HStack(spacing: Geo.Menu.rowGap) {
                        Circle().fill(o.dot ?? .clear)
                            .overlay { if o.dot == nil { Circle().strokeBorder(t.muted, lineWidth: 1.5) } }
                            .frame(width: 8, height: 8)
                        Text(o.label)
                        Spacer(minLength: 0)
                        if let count = o.count { Text("\(count)").font(Typo.ui(11)).foregroundStyle(t.faint) }
                        Icon(.check, size: 12, stroke: 3)
                            .opacity(o.id == selected ? 1 : 0)
                            .frame(width: Geo.Menu.checkSlot)
                    }
                    .font(Typo.ui(Geo.Menu.font, .medium))
                    .foregroundStyle(t.text)
                    .padding(.horizontal, Geo.Menu.rowPadX)
                    .frame(height: Geo.Menu.rowHeight)
                    .background(RoundedRectangle(cornerRadius: Geo.Menu.rowRadius).fill(o.id == selected ? t.ctrl : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(o.id == selected ? .isSelected : [])
            }
            footer
        }
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

extension Geo {
    enum NewTag {
        static let marginTop: CGFloat = 5
        static let marginSide: CGFloat = 2
        static let marginBottom: CGFloat = 2
        static let padTop: CGFloat = 6
        static let fieldHeight: CGFloat = 30
        static let fieldRadius: CGFloat = 8
        static let fieldPad = (leading: CGFloat(8), trailing: CGFloat(3))
        static let gap: CGFloat = 6
        static let font: CGFloat = 12.5
        static let inputHeight: CGFloat = 24
        static let addHeight: CGFloat = 22
        static let addPadX: CGFloat = 8
        static let addRadius: CGFloat = 6
        static let addFont: CGFloat = 11.5
        static let hintFont: CGFloat = 11
        static let hintPad = (top: CGFloat(6), side: CGFloat(6), bottom: CGFloat(2))
    }
}

/// Bottom of the assign-tag menu: divider, `# New tag [Add]` field, hint. Enter adds, Esc closes the menu.
struct NewTagField: View {
    @Binding var text: String
    var canAdd: Bool
    var onAdd: () -> Void = {}
    var onCancel: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Geo.NewTag.gap) {
                Text("#").font(Typo.ui(Geo.NewTag.font, .bold)).foregroundStyle(t.faint)
                DockTextField(text: $text, placeholder: "New tag", font: Typo.ui(Geo.NewTag.font))
                    .frame(height: Geo.NewTag.inputHeight)
                    .onSubmit(onAdd)
                    .onKeyPress(.escape) { onCancel(); return .handled }
                Button(action: onAdd) {
                    Text("Add")
                        .font(Typo.ui(Geo.NewTag.addFont, .bold))
                        .foregroundStyle(canAdd ? Tokens.onTint : t.offFg)
                        .padding(.horizontal, Geo.NewTag.addPadX)
                        .frame(height: Geo.NewTag.addHeight)
                        .background(RoundedRectangle(cornerRadius: Geo.NewTag.addRadius).fill(canAdd ? t.accent : t.btnOff))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            .padding(.leading, Geo.NewTag.fieldPad.leading + 1)
            .padding(.trailing, Geo.NewTag.fieldPad.trailing + 1)
            .frame(height: Geo.NewTag.fieldHeight)
            .background(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).fill(t.inset))
            .overlay(RoundedRectangle(cornerRadius: Geo.NewTag.fieldRadius).strokeBorder(t.border, lineWidth: 1))

            Text("Typing #tag in the todo works too")
                .font(Typo.ui(Geo.NewTag.hintFont))
                .foregroundStyle(t.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Geo.NewTag.hintPad.top)
                .padding(.horizontal, Geo.NewTag.hintPad.side)
                .padding(.bottom, Geo.NewTag.hintPad.bottom)
        }
        .padding(.top, Geo.NewTag.padTop)
        .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
        .padding(.top, Geo.NewTag.marginTop)
        .padding(.horizontal, Geo.NewTag.marginSide)
        .padding(.bottom, Geo.NewTag.marginBottom)
    }
}
