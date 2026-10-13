import SwiftUI

/// Open panel chrome (DESIGN_SPEC §3): top row beside the hardware notch, content area, footer.
/// Notes is real (M3); the other tabs are empty until their milestones.
struct OpenPanelView: View {
    var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            TopRow(model: model)
            switch model.mainTab {
            case .notes: NotesScreen(model: model)
            case .emulator: EmulatorScreen(model: model)
            case .claudex: ClaudexScreen(model: model)
            }
            Footer(model: model)
                .padding(.top, Geo.Chrome.footerTop)
        }
        .padding(.horizontal, Geo.Chrome.insetX)
        .padding(.bottom, Geo.Chrome.insetBottom)
        .frame(width: Geo.open.width, height: Geo.open.height, alignment: .top)
        .overlay(alignment: .topTrailing) {
            if model.settings {
                AppearancePopover(theme: model.theme, systemIsDark: model.appearance.isDark, tint: model.tint, onTheme: model.setTheme, onTint: model.setTint, onClose: model.toggleSettings)
                    .padding(.top, Geo.Chrome.popoverTop).padding(.trailing, Geo.Chrome.popoverRight)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Geo.popoverFade), value: model.settings)
        .overlay { DetailOverlay(store: model.claudex) }
        .overlay { ConfirmOverlay(confirmer: model.confirmer) }
        .foregroundStyle(model.tokens.text)
    }
}

private struct TopRow: View {
    var model: NotchModel
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 0) {
            PillTabs(items: MainTab.allCases.map { PillTabItem(id: $0.rawValue, label: $0.label, glyph: $0.glyph) },
                     selection: model.mainTab.rawValue) { id in
                model.setMainTab(MainTab(rawValue: id) ?? .notes)
            }

            Spacer(minLength: Geo.keepOutWidth)

            HStack(spacing: Geo.Chrome.rightClusterGap) {
                LocalIPChip(store: model.localIP)

                IconButton(glyph: .pin, label: "Pin panel open",
                           fill: model.pinned ? t.accent : t.ctrl,
                           fg: model.pinned ? Tokens.onTint : t.text2,
                           action: model.togglePin)
                    .accessibilityAddTraits(model.pinned ? .isSelected : [])
                IconButton(glyph: .sliders, label: "Settings",
                           fill: model.settings ? t.text : t.ctrl,
                           fg: model.settings ? t.panel : t.text2,
                           action: model.toggleSettings)
            }
        }
        .frame(height: Geo.Chrome.topRowHeight)
    }
}

private struct Footer: View {
    var model: NotchModel
    @Environment(\.tokens) private var t

    private var footerText: StatusMessage {
        func failed(_ why: String?) -> StatusMessage? { why.map { StatusMessage(text: "Could not save: \($0)", isError: true) } }
        switch model.mainTab {
        case .notes:
            if let snippets = model.activeSnippets { return failed(snippets.saveError) ?? StatusMessage(text: snippets.footer) }
            return failed(model.notes.saveError) ?? StatusMessage(text: model.notes.footer)
        case .emulator: return model.emulator.footer(model.emulatorTab)
        case .claudex: return StatusMessage(text: model.claudex.footer)
        }
    }

    var body: some View {
        HStack {
            Text(footerText.text).foregroundStyle(footerText.isError ? t.orange : t.faint)
            Spacer()
            HStack(spacing: Geo.Chrome.footerGap) {
                if let snippets = model.activeSnippets, snippets.deleted != nil {
                    DockButton(title: "Undo", glyph: nil, metrics: ButtonMetrics(height: Geo.Chrome.footerButtonHeight, radius: Geo.Chrome.footerButtonRadius, padLeading: Geo.Chrome.footerButtonPaddingX, padTrailing: Geo.Chrome.footerButtonPaddingX, font: 12),
                               tone: .tint, weight: .bold, action: snippets.undo)
                }
                HStack(spacing: 0) {
                    Text("⌥Space").font(Typo.mono(12)).foregroundStyle(t.text2)
                    Text(" toggle")
                }
                Button(action: model.closePanel) {
                    Text("Collapse")
                        .font(Typo.ui(12, .semibold))
                        .foregroundStyle(t.text2)
                        .padding(.horizontal, Geo.Chrome.footerButtonPaddingX)
                        .frame(height: Geo.Chrome.footerButtonHeight)
                        .background(RoundedRectangle(cornerRadius: Geo.Chrome.footerButtonRadius).fill(t.ctrl))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(Typo.ui(12))
        .foregroundStyle(t.faint)
        .padding(.top, Geo.Chrome.footerPaddingTop + 1) // + the 1 pt border-top, which is a row of its own in CSS
        .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
    }
}

/// Scrim over the whole panel plus the confirm sheet at the bottom (DESIGN_SPEC §5 claudex › Confirm sheet).
private struct ConfirmOverlay: View {
    var confirmer: Confirmer

    var body: some View {
        if let r = confirmer.pending {
            ZStack(alignment: .bottom) {
                Scrim().contentShape(Rectangle()).onTapGesture(perform: confirmer.cancel)
                ConfirmSheet(title: r.title, command: r.command, note: r.note, confirmTitle: r.confirmTitle, danger: r.danger,
                             onCancel: confirmer.cancel, onConfirm: confirmer.confirm)
                    .padding(.horizontal, Geo.Sheet.insetX)
                    .padding(.bottom, Geo.Sheet.bottom)
            }
            .transition(.opacity)
        }
    }
}
