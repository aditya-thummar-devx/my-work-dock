#if DEBUG
import SwiftUI
import AppKit

/// Offscreen renderer for pixel comparison with `screenshots/`.
///
///     MyWorkDock --snapshot <state> --out <file.png>   renders one state at 2x and exits
///     MyWorkDock --snapshot list                       prints every state name
///     MyWorkDock --snapshot region <state>             prints "x,y,w,h" (px) of a fragment's compared region
///     (optional) --font system                         SF Pro instead of Geist
///
/// Every state is a pure function of `NotchModel` + `SampleData` (the data Prototype.dc.html's `renderVals`
/// uses): no shell calls, no clock, no pointer. States draw on a `#1C1C24` desktop and are cropped like the
/// reference captures. Text defaults to Geist because the references were captured without SF Pro.
///
/// State kinds:
///  - screen states (`01-idle`): the shell in some mode, same name as the reference PNG;
///  - fragments (`03-notes-todo@subnav`): one component at its exact on-screen position over the open panel,
///    compared against only that region of the `03-notes-todo` reference;
///  - gallery (`gallery-dark`, `gallery-light`): every component, no reference.
///
/// Exit codes: 0 ok, 2 bad arguments, 3 unknown state, 4 render failed.
@MainActor
enum SnapshotRunner {
    /// Canvas + crop of a reference capture (README in `screenshots/`). All sizes in points; output is 2x.
    enum Canvas {
        /// `screenshots/artboards/*`: whole 1040 × 600 artboard, shell centred at x = 520.
        case artboard
        /// `screenshots/prototype/*` open-panel crops: 840 × 520 from the 1280 × 800 desktop.
        case panel
        /// `screenshots/prototype/*` notch strips (idle, peek, live): 880 × 120 from the same desktop.
        case notch
        /// `screenshots/prototype/34-36`: the header's IP chip and its neighbours, 300 × 60 from the same desktop.
        case chip
        /// Component gallery: no reference, a tall sheet.
        case gallery

        var size: CGSize {
            switch self {
            case .artboard: CGSize(width: 1040, height: 600)
            case .panel, .notch, .chip: CGSize(width: 1280, height: 800)
            case .gallery: CGSize(width: 1040, height: Gallery.height)
            }
        }

        var crop: CGRect {
            switch self {
            case .artboard, .gallery: CGRect(origin: .zero, size: size)
            case .panel: CGRect(x: 220, y: 0, width: 840, height: 520)
            case .notch: CGRect(x: 200, y: 0, width: 880, height: 120)
            case .chip: CGRect(x: 760, y: 0, width: 300, height: 60)
            }
        }

        /// Left edge of the 760 pt open panel on the canvas.
        var panelX: CGFloat { (size.width - Geo.open.width) / 2 }
    }

    enum Content {
        case shell
        /// A component at `rect` (panel coordinates, pt). `view == nil` compares the open-panel chrome itself.
        case fragment(rect: CGRect, view: (() -> AnyView)?)
        case gallery
    }

    struct State {
        var name: String
        var canvas: Canvas
        var content: Content = .shell
        var liveProgress: Double?
        var configure: @MainActor (NotchModel) -> Void

        init(_ name: String, _ canvas: Canvas, content: Content = .shell, liveProgress: Double? = nil,
             _ configure: @escaping @MainActor (NotchModel) -> Void = { _ in }) {
            self.name = name
            self.canvas = canvas
            self.content = content
            self.liveProgress = liveProgress
            self.configure = configure
        }

        /// Fragment of an open panel. `theme` / `tint` / `tab` / `settings` set the model; `rect` is in panel points.
        static func fragment<V: View>(_ name: String, _ canvas: Canvas = .panel, theme: ThemeMode = .dark, tint: Tint = .lime,
                                      tab: MainTab = .notes, settings: Bool = false, rect: CGRect, @ViewBuilder _ view: @escaping () -> V) -> State {
            State(name, canvas, content: .fragment(rect: rect, view: { AnyView(view()) })) {
                $0.setTheme(theme)
                $0.setTint(tint)
                $0.mainTab = tab
                if settings { $0.toggleSettings() } // the real top row and footer around a settings fragment
                $0.openPanel()
            }
        }

        /// Fragment that is just a region of the open-panel chrome.
        static func chrome(_ name: String, _ canvas: Canvas = .panel, theme: ThemeMode = .dark, tab: MainTab = .notes, rect: CGRect,
                           prepare: @escaping @MainActor (NotchModel) -> Void = { _ in }) -> State {
            State(name, canvas, content: .fragment(rect: rect, view: nil)) {
                $0.setTheme(theme)
                $0.mainTab = tab
                prepare($0)
                $0.openPanel()
            }
        }

        /// Compared region in pixels of the cropped reference image (2x).
        var regionPx: CGRect? {
            guard case .fragment(let rect, _) = content else { return nil }
            let c = canvas.crop
            return CGRect(x: (canvas.panelX - c.minX + rect.minX) * 2, y: (rect.minY - c.minY) * 2,
                          width: rect.width * 2, height: rect.height * 2)
        }
    }

    /// The open panel's content area (medium size): below the top row, above the footer. Where the settings screen draws.
    static let settingsRect = CGRect(x: Geo.Chrome.insetX, y: Geo.Chrome.topRowHeight, width: 720, height: 371)

    /// Names match the reference PNGs in `screenshots/artboards` and `screenshots/prototype`.
    /// States whose content isn't built yet are not listed; `compare-all.sh` reports them as missing.
    static let states: [State] = screenStates + Fragments.all + CalendarStates.all + BuddyStates.all + [
        State("settings-clipboard", .panel, content: .fragment(rect: settingsRect,
                                                               view: { AnyView(SettingsScreen(theme: .dark, tint: .lime, page: .clipboard, clipboardLimit: 500).onPanel()) })) { $0.toggleSettings(); $0.openPanel() },
        // Settings › Menus: the screen is as tall as the panel's content area, so this shows whether every row still fits.
        State("settings-menus", .panel, content: .fragment(rect: settingsRect,
                                                           view: { AnyView(SettingsScreen(theme: .dark, tint: .lime, page: .menus).onPanel()) })) { $0.toggleSettings(); $0.openPanel() },
        // Some sub-tabs off: Notes keeps only TODO (its switch is locked), and Emulator is off so its tabs are not listed.
        State("settings-menus-subs", .panel, content: .fragment(rect: settingsRect,
                                                                view: { AnyView(SettingsScreen(theme: .dark, tint: .lime, disabled: [.emulator],
                                                                                               disabledSubs: [.notesCommands, .notesPrompts, .notesLinks, .claudexHealth],
                                                                                               page: .menus).onPanel()) })) { $0.toggleSettings(); $0.openPanel() },
        State("settings-version", .panel, content: .fragment(rect: settingsRect,
                                                             view: { AnyView(SettingsScreen(theme: .dark, tint: .lime, page: .version, version: "0.1.0 (1)",
                                                                                            updatedAt: Date(timeIntervalSince1970: 1_790_000_000), onCheckForUpdates: {}).onPanel()) })) { $0.toggleSettings(); $0.openPanel() },
        State("gallery-dark", .gallery, content: .gallery) { $0.setTheme(.dark) },
        State("gallery-light", .gallery, content: .gallery) { $0.setTheme(.light) },
        State("60-agents", .panel) { m in m.agents.loadSample(); m.setMainTab(.claude); m.setClaudeTab(.agents); m.openPanel() },
        State("61-sessions", .panel) { m in m.sessions.loadSample(); m.setMainTab(.claude); m.setClaudeTab(.sessions); m.openPanel() },
        State("66-claude-agents-loading", .panel) { m in m.setMainTab(.claude); m.setClaudeTab(.agents); m.openPanel() },
        State("67-claude-agents-empty", .panel) { m in m.agents.showSampleEmpty(); m.setMainTab(.claude); m.setClaudeTab(.agents); m.openPanel() },
        State("68-claude-sessions-loading", .panel) { m in m.setMainTab(.claude); m.setClaudeTab(.sessions); m.openPanel() },
        State("69-claude-sessions-empty", .panel) { m in
            m.sessions.setTranscriptsForTesting([]); m.setMainTab(.claude); m.setClaudeTab(.sessions); m.openPanel()
        },
    ]

    private static let screenStates: [State] = [
        // The prototype's plain notch: the buddy states (BuddyStates) draw it with the ear.
        State("01-idle", .notch) { $0.setBuddy(BuddyPrefs(on: false)) },
        // The prototype's peek is claudex's; Settings › Peek has it off by default.
        State("02-peek-pool", .notch) {
            $0.setPeekEnabled(.claudex, true)
            $0.pointer(inside: true)
        },
        State("31-peek-after-boot", .notch) {
            $0.setPeekEnabled(.claudex, true)
            $0.pointer(inside: true)
        },
        State("32-peek-sso", .notch) {
            $0.setPeekEnabled(.claudex, true)
            $0.setPeek(SampleData.peekSSO)
            $0.pointer(inside: true)
        },
        // The reference was captured part-way through the fake boot fill.
        State("30-live-activity", .notch, liveProgress: 0.326) { $0.bootingOverride = SampleData.bootingSim },
        State("03-notes-todo", .panel) { $0.openPanel() },
        State("clipboard", .panel) {
            $0.mainTab = .clipboard
            $0.openPanel()
        },
        State("clipboard-tag-menu", .panel) {
            $0.mainTab = .clipboard
            $0.clipboard.openTagPicker(2)
            $0.openPanel()
        },
        State("clipboard-tag-manage", .panel) {
            $0.mainTab = .clipboard
            $0.clipboard.openTagManage()
            $0.openPanel()
        },
        State("clipboard-tag-form", .panel) {
            $0.mainTab = .clipboard
            $0.clipboard.openTagManage()
            $0.clipboard.openTagForm(editing: "dev")
            $0.openPanel()
        },
        State("clipboard-tag-filter", .panel) {
            $0.mainTab = .clipboard
            $0.clipboard.pickFilter("dev")
            $0.openPanel()
        },
        State("clipboard-hint", .panel) {
            $0.mainTab = .clipboard
            $0.clipboard.showHint()
            $0.openPanel()
        },
        State("clipboard-search", .panel) {
            $0.mainTab = .clipboard
            $0.clipboard.openSearch()
            $0.clipboard.query = "a"
            $0.openPanel()
        },
        State("34-header-ip-refreshing", .chip) {
            $0.openPanel()
            $0.localIP.show(.busy, ip: "192.168.1.24")
        },
        State("35-header-ip-copied", .chip) {
            $0.openPanel()
            $0.localIP.show(.copied, ip: "192.168.1.24")
        },
        State("36-header-ip-new", .chip) {
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        State("04-todo-tag-menu", .panel) {
            $0.notes.toggleTagMenu()
            $0.openPanel()
        },
        State("05-todo-tag-menu-new-tag", .panel) {
            $0.notes.toggleTagMenu()
            $0.notes.openTagForm()
            $0.notes.newTag = "design"
            $0.openPanel()
        },
        State("06-todo-tag-assigned", .panel) {
            designTag($0)
            $0.notes.draft = "Polish notch spring animation"
            $0.openPanel()
        },
        State("07-todo-added-with-new-tag", .panel) {
            prototypeNotes($0, .todo)
            $0.openPanel()
        },
        State("08-todo-filter-menu", .panel) {
            prototypeNotes($0, .todo)
            $0.notes.toggleFilterMenu()
            $0.openPanel()
        },
        State("09-todo-filtered-bug", .panel) {
            prototypeNotes($0, .todo)
            $0.notes.pickFilter("bug")
            $0.openPanel()
        },
        State("10-todo-search", .panel) {
            prototypeNotes($0, .todo)
            $0.notes.openSearch()
            $0.notes.query = "pod"
            $0.openPanel()
        },
        State("11-todo-search-empty", .panel) {
            prototypeNotes($0, .todo)
            $0.notes.openSearch()
            $0.notes.query = "zzz"
            $0.openPanel()
        },
        // Settings and light shots come after the IP chip was refreshed once (…31).
        State("19-notes-prompts-search", .panel) {
            prototypeNotes($0, .prompts)
            addedPrompt($0)
            $0.prompts.openSearch()
            $0.prompts.query = "release"
            $0.openPanel()
        },
        State("20-notes-prompts-search-empty", .panel) {
            prototypeNotes($0, .prompts)
            addedPrompt($0)
            $0.prompts.openSearch()
            $0.prompts.query = "zzz"
            $0.openPanel()
        },
        // Nothing saved yet: the add bar and the empty-list text.
        State("21-notes-commands-empty", .panel) {
            prototypeNotes($0, .commands)
            for item in $0.commands.items { $0.commands.delete(item.id) }
            $0.openPanel()
        },
        State("22-notes-prompts-empty", .panel) {
            prototypeNotes($0, .prompts)
            for item in $0.prompts.items { $0.prompts.delete(item.id) }
            $0.openPanel()
        },
        // Notes › Links (no prototype shot): the list, and with the search open.
        State("47-notes-links", .panel) {
            prototypeNotes($0, .links)
            $0.openPanel()
        },
        State("48-notes-links-search", .panel) {
            prototypeNotes($0, .links)
            $0.links.openSearch()
            $0.links.query = "github"
            $0.openPanel()
        },
        State("37-settings-appearance-dark", .panel) {
            $0.setTheme(.dark)
            tunnelWithSettings($0)
        },
        State("38-settings-appearance-light", .panel) {
            $0.setTheme(.light)
            tunnelWithSettings($0)
        },
        State("39-settings-system-following-light", .panel) {
            $0.setTheme(.system)
            $0.appearance.set(isDark: false)
            tunnelWithSettings($0)
        },
        State("40-settings-system-following-dark", .panel) {
            $0.setTheme(.system)
            $0.appearance.set(isDark: true)
            tunnelWithSettings($0)
        },
        State("41-light-emulator-tunnel", .panel) {
            $0.setTheme(.light)
            $0.mainTab = .emulator
            $0.emulatorTab = .tunnel
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        State("42-light-notes-todo", .panel) {
            $0.setTheme(.light)
            prototypeNotes($0, .todo)
            $0.prompts.draft = ""
            addedPrompt($0)
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        State("43-light-notes-prompts", .panel) {
            $0.setTheme(.light)
            prototypeNotes($0, .prompts)
            addedPrompt($0)
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        State("44-light-claudex-pool", .panel) {
            $0.setTheme(.light)
            $0.mainTab = .claudex
            $0.claudex.select(.pool)
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        State("45-light-claudex-usage", .panel) {
            $0.setTheme(.light)
            $0.mainTab = .claudex
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        State("46-settings-tint-blue", .panel) {
            $0.setTheme(.dark)
            $0.setTint(.blue)
            $0.mainTab = .claudex
            $0.toggleSettings()
            $0.openPanel()
            $0.localIP.show(.idle, ip: "192.168.1.31")
        },
        // No reference design: Settings › Menus and what the panel / peek show when menus are off.
        State.fragment("47-settings-menus-dark", settings: true, rect: settingsRect) {
            SettingsScreen(theme: .dark, tint: .lime, disabled: [.emulator], page: .menus).onPanel()
        },
        State.fragment("48-settings-menus-light", theme: .light, settings: true, rect: settingsRect) {
            SettingsScreen(theme: .light, tint: .lime, disabled: [.claudex, .localIP], page: .menus).onPanel()
        },
        State("49-menus-all-off", .panel) { model in
            Feature.allCases.forEach { model.setEnabled($0, false) }
            model.openPanel()
        },
        // No reference design: claudex off (the default) shows TODO and clip counts left of the notch, the IP on its right.
        // A part with nothing to show is hidden and the rest keep their side.
        State("50-peek-claudex-off", .notch) { $0.pointer(inside: true) },
        State("51-peek-ip", .notch) {
            $0.setPeekEnabled(.todo, false)
            $0.setPeekEnabled(.clipboard, false)
            $0.pointer(inside: true)
        },
        State("55-peek-clipboard", .notch) {
            $0.setPeekEnabled(.todo, false)
            $0.setPeekEnabled(.localIP, false)
            $0.pointer(inside: true)
        },
        State("56-peek-todo-clips", .notch) {
            $0.setPeekEnabled(.localIP, false)
            $0.pointer(inside: true)
        },
        State("57-peek-info-light", .notch) {
            $0.setTheme(.light)
            $0.pointer(inside: true)
        },
        State("52-peek-hint", .notch) {
            for source in PeekSource.allCases where source != .claudex { $0.setPeekEnabled(source, false) }
            $0.pointer(inside: true)
        },
        // No reference design: Settings › Peek, with claudex off (default) and on (the others wait, dimmed).
        State.fragment("53-settings-peek-dark", settings: true, rect: settingsRect) {
            SettingsScreen(theme: .dark, tint: .lime, peekOn: [.clipboard, .localIP], page: .peek).onPanel()
        },
        State.fragment("54-settings-peek-light-claudex", theme: .light, settings: true, rect: settingsRect) {
            SettingsScreen(theme: .light, tint: .lime, peekOn: [.claudex], page: .peek).onPanel()
        },
        State("16-notes-prompts-multiline-input", .panel) {
            prototypeNotes($0, .prompts)
            $0.prompts.draft = newPromptText
            $0.openPanel()
        },
        State("17-notes-prompts-added", .panel) {
            prototypeNotes($0, .prompts)
            addedPrompt($0)
            $0.openPanel()
        },
        State("18-notes-prompts-editing", .panel) {
            prototypeNotes($0, .prompts)
            addedPrompt($0)
            $0.prompts.startEdit(6)
            $0.openPanel()
        },
        State("12-notes-commands", .panel) {
            prototypeNotes($0, .commands)
            $0.openPanel()
        },
        State("13-notes-commands-editing", .panel) {
            prototypeNotes($0, .commands)
            $0.commands.startEdit(1)
            $0.openPanel()
        },
        State("14-notes-commands-copied", .panel) {
            prototypeNotes($0, .commands)
            $0.commands.showCopied(1)
            $0.openPanel()
        },
        State("15-notes-prompts", .panel) {
            prototypeNotes($0, .prompts)
            $0.openPanel()
        },
        State("17-emulator-devices-ios", .panel) {
            $0.mainTab = .emulator
            $0.emulator.platform = .ios
            $0.openPanel()
        },
        State("18-emulator-devices-android", .panel) {
            $0.mainTab = .emulator
            $0.emulator.platform = .android
            $0.openPanel()
        },
        State("19-emulator-wireless", .panel) {
            $0.mainTab = .emulator
            $0.emulatorTab = .wireless
            $0.emulator.wplatform = .ios
            $0.openPanel()
        },
        State("20-emulator-tunnel", .panel) {
            $0.mainTab = .emulator
            $0.emulatorTab = .tunnel
            $0.openPanel()
        },
        State("29-emulator-booting", .panel) {
            $0.mainTab = .emulator
            $0.emulator.platform = .ios
            $0.emulator.showBootingSample()
            $0.openPanel()
        },
        State("08-claudex-usage", .panel) {
            $0.mainTab = .claudex
            $0.openPanel()
        },
        State("09-claudex-sort-menu", .panel) {
            $0.mainTab = .claudex
            $0.claudex.sortOpen = true
            $0.openPanel()
        },
        State("10-claudex-confirm-switch", .panel) {
            $0.mainTab = .claudex
            $0.claudex.switchAccount("studio")
            $0.openPanel()
        },
        State("11-claudex-confirm-remove", .panel) {
            $0.mainTab = .claudex
            $0.claudex.removeAccount("studio")
            $0.openPanel()
        },
        State("12-claudex-pool", .panel) {
            $0.mainTab = .claudex
            $0.claudex.select(.pool)
            $0.openPanel()
        },
        State("13-claudex-pool-details", .panel) {
            $0.mainTab = .claudex
            $0.claudex.select(.pool)
            $0.claudex.showSampleDetail()
            $0.openPanel()
        },
        State("14-claudex-pool-details-raw", .panel) {
            $0.mainTab = .claudex
            $0.claudex.select(.pool)
            $0.claudex.showSampleDetail()
            $0.claudex.rawOn = true
            $0.openPanel()
        },
        State("15-claudex-playground", .panel) {
            $0.mainTab = .claudex
            $0.claudex.select(.play)
            $0.claudex.showSampleOutput()
            $0.openPanel()
        },
        State("16-claudex-health", .panel) {
            $0.mainTab = .claudex
            $0.claudex.select(.health)
            $0.openPanel()
        },
        // No reference design: Claude › Tokens & cost, from Claude Code's transcripts. It works without claudex.
        State("58-claude-tokens", .panel) {
            $0.mainTab = .claude
            $0.setClaudeTab(.tokens)
            $0.openPanel()
        },
        State("59-claude-tokens-partial", .panel) {
            $0.mainTab = .claude
            $0.setClaudeTab(.tokens)
            $0.claudeUsage.showSamplePartial()
            $0.openPanel()
        },
        State("60-claudex-missing", .panel) {
            $0.mainTab = .claudex
            $0.claudex.showSampleUnavailable()
            $0.openPanel()
        },
        State("61-claude-tokens-empty", .panel) {
            $0.mainTab = .claude
            $0.setClaudeTab(.tokens)
            $0.claudeUsage.showSampleEmpty()
            $0.openPanel()
        },
        State("62-claude-tokens-loading", .panel) {
            $0.mainTab = .claude
            $0.setClaudeTab(.tokens)
            $0.claudeUsage.showSampleLoading()
            $0.openPanel()
        },
        State("63-light-claude-tokens", .panel) {
            $0.setTheme(.light)
            $0.mainTab = .claude
            $0.setClaudeTab(.tokens)
            $0.claudeUsage.showSamplePartial()
            $0.openPanel()
        },
        // Commands that have been run once: the folder chip before Run (short name, long name truncated; the blocked one shows its lock).
        State("64-notes-commands-folders", .panel) {
            prototypeNotes($0, .commands)
            $0.commands.setFolder(1, "/Users/me/Projects/mobile-app")
            $0.commands.setFolder(2, "/Users/me/Projects/client-work/mobile-app-android-release-build")
            $0.commands.setFolder(6, "/Users/me/Projects/mobile-app")
            $0.openPanel()
        },
        State("02-notes-todo", .artboard) {
            $0.notes.pickTodoTag("bug")
            $0.notes.openSearch()
            $0.openPanel()
        },
        State("03-notes-commands", .artboard) {
            $0.setNotesTab(.commands)
            $0.openPanel()
        },
        State("03b-notes-prompts", .artboard) {
            $0.setNotesTab(.prompts)
            $0.openPanel()
        },
    ]

    /// Shots 06+ come after the tag `design` was created in 05: it exists (colour #FFD86B) and is picked for the next todo.
    static func designTag(_ model: NotchModel) {
        model.notes.toggleTagMenu()
        model.notes.openTagForm()
        model.notes.newTag = "design"
        model.notes.saveTagForm() // from the assign menu, so the tag is picked and the menu closes
    }

    /// The prototype shots 07–20 were captured after "Polish notch spring animation" had been added with the tag
    /// picked in 05/06 still selected (TODO badge 4, not 3).
    static func prototypeNotes(_ model: NotchModel, _ tab: NotesTab) {
        designTag(model)
        model.notes.draft = "Polish notch spring animation"
        model.notes.addTodo()
        model.setNotesTab(tab)
    }

    /// The prompt typed in prototype shots 16–18.
    static let newPromptText = "Summarise this diff for a client update.\n- Keep it under 5 bullets\n- No internal jargon"

    /// Prototype shots 17+: that prompt has been added (first in the list, id 6).
    static func addedPrompt(_ model: NotchModel) {
        model.prompts.draft = newPromptText
        model.prompts.add()
    }

    /// Settings shots: the Appearance screen (the Emulator › Tunnel tab it was once drawn over stays selected underneath).
    static func tunnelWithSettings(_ model: NotchModel) {
        model.mainTab = .emulator
        model.emulatorTab = .tunnel
        model.toggleSettings()
        model.openPanel()
        model.localIP.show(.idle, ip: "192.168.1.31")
    }

    /// `--start <state>`: launches the real panel already in that state (no pointer needed).
    static func applyStartState(to model: NotchModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--start"), i + 1 < args.count,
              let state = states.first(where: { $0.name == args[i + 1] }) else { return }
        model.mainTab = .notes // the reference states were captured before the Clipboard menu became the first tab
        state.configure(model)
    }

    /// Returns the exit code if the process was launched in snapshot mode, nil otherwise.
    static func runIfRequested() -> Int32? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot") else { return nil }
        func value(of flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        guard let name = value(of: "--snapshot") else { return fail("usage: --snapshot <state> --out <file.png>", 2) }
        if name == "list" {
            states.forEach { print($0.name) }
            return 0
        }
        if name == "region" {
            guard i + 2 < args.count, let r = states.first(where: { $0.name == args[i + 2] })?.regionPx else { return fail("no region for that state", 3) }
            print("\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))")
            return 0
        }
        guard let out = value(of: "--out") else { return fail("missing --out <file.png>", 2) }
        guard let state = states.first(where: { $0.name == name }) else {
            return fail("unknown state '\(name)'. Known: " + states.map(\.name).joined(separator: " "), 3)
        }
        Typo.uiFamily = value(of: "--font") == "system" ? nil : "Geist"

        let model = NotchModel(sample: true)
        model.mainTab = .notes // see applyStartState
        state.configure(model)
        let url = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return render(state, model: model, to: url) ? 0 : fail("render failed for '\(name)'", 4)
    }

    private static func fail(_ message: String, _ code: Int32) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return code
    }

    private static func render(_ state: State, model: NotchModel, to url: URL) -> Bool {
        let t = model.tokens
        let canvas = ZStack(alignment: .topLeading) {
            Color(hex: 0x1C1C24)
            switch state.content {
            case .shell:
                NotchContainer(model: model)
                cameraDot
            case .fragment(let rect, let view):
                NotchContainer(model: model)
                if let view {
                    view()
                        .foregroundStyle(t.text) // the panel sets this for everything inside it
                        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                        .padding(.leading, state.canvas.panelX + rect.minX)
                        .padding(.top, rect.minY)
                }
                cameraDot
            case .gallery:
                Gallery()
            }
        }
        .frame(width: state.canvas.size.width, height: state.canvas.size.height, alignment: .topLeading)
        .environment(\.tokens, t)
        .environment(\.entrance, false)
        .environment(\.staticRender, true)
        .environment(\.liveProgress, state.liveProgress)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let full = renderer.cgImage else { return false }
        let c = state.canvas.crop
        guard let cropped = full.cropping(to: CGRect(x: c.minX * 2, y: c.minY * 2, width: c.width * 2, height: c.height * 2)),
              let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    /// Camera mock from the designs (DESIGN_SPEC §1). Snapshot only: the real app doesn't draw it.
    private static var cameraDot: some View {
        Circle()
            .fill(Color(hex: 0x16161F))
            .overlay(Circle().strokeBorder(Color(hex: 0x22222E), lineWidth: 1.5))
            .frame(width: 8, height: 8)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

extension View {
    /// A settings screen drawn over the real panel's content area has no background of its own: give it the panel colour,
    /// or the menu underneath shows through.
    func onPanel() -> some View { modifier(OnPanel()) }
}

private struct OnPanel: ViewModifier {
    @Environment(\.tokens) private var t
    func body(content: Content) -> some View { content.background(t.panel) }
}
#endif
