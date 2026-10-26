import SwiftUI

/// Open panel chrome (DESIGN_SPEC §3): top row beside the hardware notch, content area, footer.
/// Notes is real (M3); the other tabs are empty until their milestones.
struct OpenPanelView: View {
    var model: NotchModel
    /// The shell's open size on this display (`Geo.open` unless Settings › Panel size says large).
    var size = CGSize(width: Geo.open.width, height: Geo.open.height)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            TopRow(model: model)
            // ZStack so outgoing and incoming screens overlap during the crossfade instead of sharing the VStack's height.
            ZStack(alignment: .top) {
                if model.settings {
                    SettingsScreen(theme: model.theme, systemIsDark: model.appearance.isDark, tint: model.tint, panelSize: model.panelSize,
                                   notchPosition: model.notchPosition,
                                   disabled: model.disabled, disabledSubs: model.disabledSubs, peekOn: model.peekOn,
                                   allDisplays: model.showOnAllDisplays, buddy: model.buddy,
                                   customBuddies: CustomBuddies(library: model.customBuddies, add: model.addCustomBuddy, remove: model.removeCustomBuddy,
                                                                 setFile: { model.setCustomBuddyFile($0, of: $1) }), clipboardLimit: model.clipboard.limit,
                                   calendarAutoPeek: model.calendarAutoPeekEnabled, calendarAutoPeekThreshold: model.calendarAutoPeekThreshold,
                                   version: model.version, updatedAt: model.updatedAt, onCheckForUpdates: model.checkForUpdates,
                                   onTheme: model.setTheme, onTint: model.setTint, onPanelSize: model.setPanelSize,
                                   onNotchPosition: model.setNotchPosition,
                                   onFeature: model.setEnabled, onSub: model.setEnabled, onPeek: model.setPeekEnabled,
                                   onCalendarAutoPeek: model.setCalendarAutoPeekEnabled, onCalendarAutoPeekThreshold: model.setCalendarAutoPeekThreshold,
                                   onAllDisplays: model.setShowOnAllDisplays,
                                   onBuddy: model.setBuddy, onClipboardLimit: model.setClipboardLimit)
                        .transition(.opacity)
                } else if model.enabledTabs.isEmpty {
                    MenusOffGuide(onOpenSettings: model.toggleSettings).transition(.opacity)
                } else {
                    switch model.mainTab {
                    case .clipboard: ClipboardScreen(store: model.clipboard).transition(.opacity)
                    case .calendar: CalendarScreen(store: model.calendar).transition(.opacity)
                    case .claude: ClaudeScreen(model: model).transition(.opacity)
                    case .notes: NotesScreen(model: model).transition(.opacity)
                    case .emulator: EmulatorScreen(model: model).transition(.opacity)
                    case .claudex: ClaudexScreen(model: model).transition(.opacity)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : .easeOut(duration: Geo.tabContentFade), value: model.mainTab)
            .animation(reduceMotion ? nil : .easeOut(duration: Geo.tabContentFade), value: model.settings)
            Footer(model: model)
                .padding(.top, Geo.Chrome.footerTop)
        }
        .padding(.horizontal, Geo.Chrome.insetX)
        .padding(.bottom, Geo.Chrome.insetBottom)
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay { DetailOverlay(store: model.claudex) }
        .overlay { CalendarEventOverlay(store: model.calendar) }
        .overlay { CommandRunOverlay(runner: model.runner) }
        .overlay { ConfirmOverlay(confirmer: model.confirmer) }
        .foregroundStyle(model.tokens.text)
    }
}

private struct TopRow: View {
    var model: NotchModel
    @Environment(\.tokens) private var t

    /// Collapse and Help: small rounded buttons on a `ctrl` fill.
    private func cornerButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.ui(12, .semibold))
                .foregroundStyle(t.text2)
                .padding(.horizontal, Geo.Chrome.footerButtonPaddingX)
                .frame(height: Geo.Chrome.footerButtonHeight)
                .background(RoundedRectangle(cornerRadius: Geo.Chrome.footerButtonRadius).fill(t.ctrl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Collapse in the corner, where a window's close button sits; Help next to it. The menus are the tabs in the footer.
            HStack(spacing: Geo.Chrome.rightClusterGap) {
                cornerButton("Collapse", model.closePanel)
                cornerButton("Help", model.openUsageGuide)
            }

            Spacer(minLength: Geo.keepOutWidth)

            HStack(spacing: Geo.Chrome.rightClusterGap) {
                if model.isEnabled(.localIP) { LocalIPChip(store: model.localIP) }

                IconButton(glyph: .pin, label: "Pin panel open",
                           fill: model.pinned ? t.accent : t.ctrl,
                           fg: model.pinned ? Tokens.onTint : t.text2,
                           action: model.togglePin)
                    .accessibilityAddTraits(model.pinned ? .isSelected : [])
                IconButton(glyph: .gear, label: "Settings",
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
        if model.settings { return StatusMessage(text: "Settings") }
        if model.enabledTabs.isEmpty { return StatusMessage(text: "All menus are off") }
        func failed(_ why: String?) -> StatusMessage? { why.map { StatusMessage(text: "Could not save: \($0)", isError: true) } }
        switch model.mainTab {
        case .clipboard: return failed(model.clipboard.saveError) ?? StatusMessage(text: model.clipboard.footer)
        case .calendar: return model.calendar.footer
        case .claude:
            switch model.claudeTab {
            case .tokens: return StatusMessage(text: ClaudeUsageStore.footer)
            case .agents: return StatusMessage(text: model.agents.footer)
            case .sessions: return StatusMessage(text: model.sessions.footer)
            }
        case .notes:
            if let snippets = model.activeSnippets { return failed(snippets.saveError) ?? StatusMessage(text: snippets.footer) }
            return failed(model.notes.saveError) ?? StatusMessage(text: model.notes.footer)
        case .emulator: return model.emulator.footer(model.emulatorTab)
        case .claudex: return StatusMessage(text: model.claudex.footer)
        }
    }

    var body: some View {
        // Three zones. The two outer ones take equal room, so the menu tabs stay on the exact centre line whatever the status text or
        // the right-hand items are, and the text wraps (to two lines, cut after that, all of it on hover) instead of running under them.
        // The row keeps the old 26 pt button height: the 34 pt tab capsule and a second line of text overflow it into spare padding.
        HStack(spacing: 0) {
            Text(footerText.text)
                .foregroundStyle(footerText.isError ? t.orange : t.faint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(footerText.text)
                .padding(.trailing, Geo.Chrome.footerGap)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !model.enabledTabs.isEmpty {
                PillTabs(items: model.enabledTabs.map { PillTabItem(id: $0.rawValue, label: $0.label, glyph: $0.glyph) },
                         selection: model.settings ? "" : model.mainTab.rawValue) { id in
                    model.setMainTab(MainTab(rawValue: id) ?? .notes)
                }
                .fixedSize() // its own width, never a third of the row; the two zones around it then split the rest equally
            }

            HStack(spacing: Geo.Chrome.footerGap) {
                if let undo = model.pendingUndo {
                    DockButton(title: "Undo", glyph: nil, metrics: ButtonMetrics(height: Geo.Chrome.footerButtonHeight, radius: Geo.Chrome.footerButtonRadius, padLeading: Geo.Chrome.footerButtonPaddingX, padTrailing: Geo.Chrome.footerButtonPaddingX, font: 12),
                               tone: .tint, weight: .bold, action: undo)
                }
                HStack(spacing: 0) {
                    Text("⌥Space").font(Typo.mono(12)).foregroundStyle(t.text2)
                    Text(" toggle")
                }
            }
            .padding(.leading, Geo.Chrome.footerGap)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: Geo.Chrome.footerButtonHeight)
        .font(Typo.ui(12))
        .foregroundStyle(t.faint)
        .padding(.top, Geo.Chrome.footerPaddingTop + 1) // + the 1 pt border-top, which is a row of its own in CSS
        .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
    }
}

/// Every menu switched off: the content area explains how to get one back.
private struct MenusOffGuide: View {
    var onOpenSettings: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(spacing: 10) {
            Icon(.gear, size: 26).foregroundStyle(t.muted)
            Text("All menus are off").font(Typo.display(18)).tracking(-0.4)
            Text("Open Settings with the gear button at the top right, choose Menus, and switch one on.")
                .font(Typo.ui(13))
                .foregroundStyle(t.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            DockButton(title: "Open settings", glyph: .gear,
                       metrics: ButtonMetrics(height: Geo.Chrome.footerButtonHeight, radius: Geo.Chrome.footerButtonRadius, padLeading: Geo.Chrome.footerButtonPaddingX, padTrailing: Geo.Chrome.footerButtonPaddingX, font: 12),
                       tone: .tint, weight: .bold, action: onOpenSettings)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Scrim over the whole panel plus the confirm sheet at the bottom (DESIGN_SPEC §5 claudex › Confirm sheet).
private struct ConfirmOverlay: View {
    var confirmer: Confirmer

    var body: some View {
        if let r = confirmer.pending {
            ZStack(alignment: .bottom) {
                Scrim().contentShape(Rectangle()).onTapGesture(perform: confirmer.cancel)
                ConfirmSheet(title: r.title, command: r.command, note: r.note, confirmTitle: r.confirmTitle, danger: r.danger, commandLines: r.commandLines,
                             onCancel: confirmer.cancel, onConfirm: confirmer.confirm)
                    .padding(.horizontal, Geo.Sheet.insetX)
                    .padding(.bottom, Geo.Sheet.bottom)
            }
            .transition(.opacity)
        }
    }
}
