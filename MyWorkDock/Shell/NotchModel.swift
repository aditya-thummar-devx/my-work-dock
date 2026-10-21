import SwiftUI
import Observation

typealias DisplayID = CGDirectDisplayID

enum MainTab: String, CaseIterable, Identifiable {
    case clipboard, calendar, notes, claudex, emulator

    var id: String { rawValue }
    var label: String {
        switch self {
        case .claudex: "claudex"
        case .calendar: "My Calendar"
        default: rawValue.capitalized
        }
    }
    var glyph: Glyph {
        switch self {
        case .clipboard: .clipboard
        case .calendar: .calendar
        case .notes: .notes
        case .claudex: .gauge
        case .emulator: .phone
        }
    }
    var feature: Feature {
        switch self {
        case .clipboard: .clipboard
        case .calendar: .calendar
        case .notes: .notes
        case .claudex: .claudex
        case .emulator: .emulator
        }
    }
}

/// What Settings › Menus can switch off. The raw values are stored in UserDefaults.
enum Feature: String, CaseIterable, Identifiable {
    case clipboard, calendar, notes, claudex, emulator, localIP

    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: "Clipboard"
        case .calendar: "My Calendar"
        case .notes: "Notes"
        case .claudex: "claudex"
        case .emulator: "Emulator"
        case .localIP: "Local IP"
        }
    }
    var glyph: Glyph {
        switch self {
        case .clipboard: .clipboard
        case .calendar: .calendar
        case .notes: .notes
        case .claudex: .gauge
        case .emulator: .phone
        case .localIP: .wifi
        }
    }
}

/// Everything the shell animates: size, bottom radius and horizontal offset from the hardware-notch centre.
struct ShellGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var centerOffset: CGFloat = 0
    var shoulder: CGFloat = Geo.shoulder
}

/// idle ──hover──▶ peek ──click──▶ open; leaving starts a 350 ms timer (DESIGN_SPEC §1).
@MainActor @Observable
final class NotchModel {
    private(set) var hover = false
    private(set) var open = false
    private(set) var pinned = false
    private(set) var settings = false
    /// True when the last mode change made the shell smaller; the container then uses the shrink curve.
    private(set) var shrinking = false
    var mainTab: MainTab = .clipboard
    var notesTab: NotesTab = .todo
    let clipboard: ClipboardStore
    let notes: NotesStore
    let commands: SnippetStore
    let prompts: SnippetStore
    let links: SnippetStore
    let confirmer: Confirmer
    let emulator: EmulatorStore
    let claudex: ClaudexStore
    let localIP: LocalIPStore
    let calendar: CalendarStore
    /// The user's choice; `resolvedTheme` is what is drawn.
    private(set) var theme: ThemeMode = .dark
    let appearance: AppearanceObserver
    private(set) var tint: Tint = .lime
    /// Settings › Appearance: size of the open panel.
    private(set) var panelSize: PanelSize = .medium
    /// Settings › Menus: a disabled feature is hidden and runs nothing in the background.
    private(set) var disabled: Set<Feature> = []
    /// Settings › Peek: the sources hover shows. `[.claudex]` alone, or any of the others (claudex takes the whole hover).
    private(set) var peekOn: Set<PeekSource> = PeekSource.defaultOn
    var emulatorTab: EmulatorTab = .devices
    /// Forces the live-activity state (debug menu, snapshots); otherwise it follows the emulator store.
    var bootingOverride: String?
    private(set) var peek = SampleData.peekPool
    private(set) var peekExtents = PeekExtents(left: 0, right: 0)
    /// The events row under the ears (Settings › Peek › Today's events); nil when it is off or nothing is loaded to show. Stored,
    /// not computed: the window layer reads the geometry on every pointer move, so this is re-read only when hover starts and
    /// when a fetch lands.
    private(set) var peekEvents: PeekEvents?
    /// Settings › Menus: also draw the shell on every other display. Off = one shell on the notch (or pointer) display.
    private(set) var showOnAllDisplays = false
    /// Settings › Version: "1.0 (1)", and when this version first ran here (an install or an update). nil in snapshots and tests.
    let version = NotchModel.versionLabel
    private(set) var updatedAt: Date?
    /// Display whose shell peeks / opens; the others stay idle. nil (snapshots) = every shell follows `mode`.
    private(set) var activeDisplay: DisplayID?

    /// Called after every state change so the window layer can update hit-testing and key status.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Set by the app delegate once the updater runs (release builds only); nil hides "Check for Updates…".
    @ObservationIgnored var checkForUpdates: (() -> Void)?
    static let usageGuideURL = URL(string: "https://aditya-thummar-devx.github.io/my-work-dock/usage.html")!
    /// Settings › Version and the menu-bar menu. The panel floats above other windows, so close it before the browser opens.
    func openUsageGuide() {
        closePanel()
        NSWorkspace.shared.open(Self.usageGuideURL)
    }
    /// Schedules `work` after `delay` seconds and returns a cancel closure. Injected by tests.
    @ObservationIgnored var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void = { delay, work in
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
    @ObservationIgnored private var cancelLeave: (() -> Void)?
    @ObservationIgnored private var lastRank = NotchMode.idle.rank

    /// `sample: true` keeps every store in memory with the designs' sample data (snapshots, tests).
    @ObservationIgnored private let defaults: UserDefaults?

    init(sample: Bool = false) {
        defaults = sample ? nil : .standard
        appearance = sample ? AppearanceObserver(isDark: true) : .live()
        if let defaults {
            theme = defaults.string(forKey: "theme").flatMap(ThemeMode.init(rawValue:)) ?? .system
            tint = defaults.string(forKey: "tint").flatMap(Tint.init(rawValue:)) ?? .lime
            panelSize = defaults.string(forKey: "panelSize").flatMap(PanelSize.init(rawValue:)) ?? .medium
            disabled = Set((defaults.stringArray(forKey: "disabledFeatures") ?? []).compactMap(Feature.init(rawValue:)))
            if let saved = defaults.stringArray(forKey: "peekSources") { peekOn = PeekSource.restored(saved) }
            showOnAllDisplays = defaults.bool(forKey: "showOnAllDisplays")
            if defaults.string(forKey: "seenVersion") != version {
                defaults.set(version, forKey: "seenVersion")
                defaults.set(Date(), forKey: "updatedAt")
            }
            updatedAt = defaults.object(forKey: "updatedAt") as? Date
        }
        clipboard = sample ? .sample() : .live()
        notes = sample ? .sample() : NotesStore()
        commands = sample ? .sample(.commands) : .persistent(.commands)
        prompts = sample ? .sample(.prompts) : .persistent(.prompts)
        links = sample ? .sample(.links) : .persistent(.links)
        let confirmer = Confirmer()
        self.confirmer = confirmer
        emulator = sample ? EmulatorStore(sample: false, confirmer: confirmer) : EmulatorStore(confirmer: confirmer)
        claudex = sample ? ClaudexStore(sample: true, confirmer: confirmer) : ClaudexStore(confirmer: confirmer)
        localIP = sample ? .sample() : .live()
        calendar = sample ? .sample() : .live(confirmer: confirmer)
        if !sample { peek = claudex.peekData } // snapshots keep the prototype's POOL sample
        peekExtents = PeekMetrics.measure(peek)
        claudex.onData = { [weak self] in self?.refreshPeek() }
        clipboard.onCopied = { [weak self] in self?.closePanel() }
        commands.onCopied = { [weak self] in self?.closePanel() }
        prompts.onCopied = { [weak self] in self?.closePanel() }
        links.onCopied = { [weak self] in self?.closePanel() }
        calendar.willOpenBrowser = { [weak self] in self?.closePanel() } // the open panel floats above the browser
        calendar.onSignedIn = { [weak self] in self?.show(.calendar) }
        if let first = enabledTabs.first, !enabledTabs.contains(mainTab) { mainTab = first }
    }

    /// Re-reads the peek from claudex; only re-measures the ears when something changed.
    func refreshPeek() {
        let data = claudex.peekData
        if data != peek { setPeek(data) }
    }

    /// Hover began (or the row was just switched on): show what is cached at once, ask Google for fresh events (reused for 60 s),
    /// and show those when they land. The only time the peek talks to the network; nothing polls.
    private func loadPeekEvents() {
        refreshPeekEvents()
        guard isPeekEnabled(.events), isEnabled(.calendar) else { return }
        Task {
            await calendar.refreshToday()
            refreshPeekEvents()
        }
    }

    /// Re-reads today's events for the row under the ears: the next three that are not over, and how many more.
    func refreshPeekEvents() {
        var next: PeekEvents?
        if isPeekEnabled(.events), isEnabled(.calendar), let upcoming = calendar.upcomingToday() {
            let rows = upcoming.prefix(Geo.Peek.eventsShown).map { PeekEvent(id: $0.id, title: $0.title, color: $0.color, start: $0.start, end: $0.end) }
            next = PeekEvents(rows: rows, more: upcoming.count - rows.count, now: calendar.now())
        }
        guard next != peekEvents else { return }
        peekEvents = next
        changed()
    }

    // MARK: Derived

    func isEnabled(_ feature: Feature) -> Bool { !disabled.contains(feature) }
    var enabledTabs: [MainTab] { MainTab.allCases.filter { isEnabled($0.feature) } }
    func isPeekEnabled(_ source: PeekSource) -> Bool { peekOn.contains(source) }

    /// What hover draws. claudex on: its two ears, or the hint while it has no account to show. Otherwise the TODO and
    /// clipboard counts (left) and the Local IP (right), each only when its source is on, its menu is on and it has
    /// something to show; with none of them, the hint invites a click.
    var peekContent: PeekContent {
        func shows(_ source: PeekSource) -> Bool { isPeekEnabled(source) && isEnabled(source.feature) }
        if isPeekEnabled(.claudex) { return shows(.claudex) && claudex.hasPeek ? .claudex : .hint }
        let info = PeekInfo(todo: shows(.todo) ? notes.peekTodo : nil,
                            clips: shows(.clipboard) ? clipboard.peekClips : nil,
                            ip: shows(.localIP) ? localIP.ip : nil)
        return info.isEmpty ? .hint : .info(info)
    }

    private var shownPeekExtents: PeekExtents {
        switch peekContent {
        case .claudex: peekExtents
        case .info(let info): PeekMetrics.measure(info)
        case .hint: PeekMetrics.hintExtents
        }
    }

    /// Simulator currently booting; drives the live-activity state. Never set while the Emulator menu is off.
    var bootingName: String? { isEnabled(.emulator) ? bootingOverride ?? emulator.bootingName : nil }

    var mode: NotchMode { open ? .open : hover ? .peek : bootingName != nil ? .live : .idle }
    var resolvedTheme: ThemeMode { theme.resolved(systemIsDark: appearance.isDark) }
    var isLight: Bool { resolvedTheme == .light }
    var tokens: Tokens { Tokens(mode: resolvedTheme, tint: tint) }

    /// Peek and open belong to the active display; the others stay idle (live mirrors everywhere).
    func mode(on display: DisplayID?) -> NotchMode {
        guard let display, let active = activeDisplay, display != active, mode == .peek || mode == .open else { return mode }
        return bootingName != nil ? .live : .idle
    }

    /// Shell size on `display`. `notch` is that display's hardware notch size in points (nil: none); idle is drawn at exactly it.
    /// `screen` is the display's size in points; the open panel scales with it when `panelSize` is large.
    func geometry(notch: CGSize? = nil, on display: DisplayID? = nil, screen: CGSize? = nil) -> ShellGeometry {
        switch mode(on: display) {
        case .idle:
            if let notch {
                Geo.hardwareNotchShell(notch)
            } else {
                ShellGeometry(width: Geo.idle.width, height: Geo.idle.height, radius: Geo.idle.radius)
            }
        case .peek:
            // The events row hangs under the ears: the shell grows by its height and is wide enough for a title. The extra width is
            // split evenly, so the ears stay where they were against the notch.
            ShellGeometry(width: max(Geo.keepOutWidth + shownPeekExtents.left + shownPeekExtents.right, peekEvents == nil ? 0 : Geo.Peek.eventsMinWidth),
                          height: Geo.peek.height + (peekEvents?.height ?? 0), radius: Geo.peek.radius,
                          centerOffset: (shownPeekExtents.right - shownPeekExtents.left) / 2)
        case .live:
            ShellGeometry(width: Geo.live.width, height: Geo.live.height, radius: Geo.live.radius)
        case .open:
            ShellGeometry(width: panelSize.size(on: screen).width, height: panelSize.size(on: screen).height, radius: Geo.open.radius)
        }
    }

    // MARK: Pointer

    /// Fed by the window layer on every mouse move with "is the pointer over the shape".
    /// Leaving arms the 350 ms timer once; re-entering cancels it. A panel opened by keyboard never
    /// arms it until the pointer has entered at least once (`hover` stays false).
    func pointer(inside: Bool) {
        if inside {
            guard !hover || cancelLeave != nil else { return }
            clearLeaveTimer()
            if !hover, isPeekEnabled(.claudex), isEnabled(.claudex) { Task { await claudex.refresh() } } // reads are cached for 60 s
            if !hover { loadPeekEvents() }
            hover = true
            changed()
        } else if hover, cancelLeave == nil {
            cancelLeave = schedule(Geo.leaveDelay) { [weak self] in self?.leaveFired() }
        }
    }

    private func leaveFired() {
        cancelLeave = nil
        hover = false
        if !pinned {
            open = false
            settings = false
            claudex.closeDetail()
            clipboard.closeMenus()
            calendar.closeMenus()
        }
        changed()
    }

    /// Store behind the visible Commands / Prompts / Links sub-tab; nil on TODO and the other main tabs.
    var activeSnippets: SnippetStore? {
        guard mainTab == .notes, isEnabled(.notes) else { return nil }
        switch notesTab {
        case .todo: return nil
        case .commands: return commands
        case .prompts: return prompts
        case .links: return links
        }
    }

    /// Footer Undo: restores the last delete in the visible Notes tab; nil when there is nothing to undo.
    var pendingUndo: (() -> Void)? {
        guard mainTab == .notes, isEnabled(.notes) else { return nil }
        if notesTab == .todo {
            guard notes.deleted != nil else { return nil }
            return notes.undo
        }
        guard let snippets = activeSnippets, snippets.deleted != nil else { return nil }
        return snippets.undo
    }

    // MARK: Actions

    /// Prototype `mainTabs.pick`: leaving a tab drops any open inline edit.
    func setMainTab(_ tab: MainTab) {
        mainTab = tab
        claudex.closeDetail()
        clipboard.closeMenus()
        calendar.closeMenus()
        notes.cancelEdit()
        commands.cancelEdit()
        prompts.cancelEdit()
        links.cancelEdit()
    }

    /// Tab key: next enabled main menu, wrapping. No-op with fewer than two.
    func cycleMainTab() {
        let tabs = enabledTabs
        guard tabs.count > 1, let i = tabs.firstIndex(of: mainTab) else { return }
        setMainTab(tabs[(i + 1) % tabs.count])
    }

    /// Shift+Tab: next sub-tab of the visible main menu, wrapping.
    func cycleInnerTab() {
        guard isEnabled(mainTab.feature) else { return }
        func next<T: CaseIterable & Equatable>(_ v: T) -> T {
            let all = Array(T.allCases)
            return all[((all.firstIndex(of: v) ?? 0) + 1) % all.count]
        }
        switch mainTab {
        case .clipboard: break
        case .calendar: calendar.cycleMode()
        case .notes: setNotesTab(next(notesTab))
        case .claudex: claudex.select(next(claudex.tab))
        case .emulator: setEmulatorTab(next(emulatorTab))
        }
    }

    func setEmulatorTab(_ tab: EmulatorTab) {
        emulatorTab = tab
        emulator.targetMenuOpen = false
    }

    /// Prototype `sub.pick`: a sub-tab switch resets edits, drafts, undo, "Copied", the search and open menus.
    func setNotesTab(_ tab: NotesTab) {
        notesTab = tab
        commands.reset()
        prompts.reset()
        links.reset()
        notes.resetTransient()
    }

    /// ⌘F while the panel is key: opens the search of the visible Clipboard or Notes tab (TODO, Prompts or Links).
    func openSearch() {
        if mainTab == .clipboard, isEnabled(.clipboard) { return clipboard.openSearch() }
        guard mainTab == .notes, isEnabled(.notes) else { return }
        switch notesTab {
        case .todo: notes.openSearch()
        case .prompts: prompts.openSearch()
        case .links: links.openSearch()
        case .commands: break
        }
    }

    /// Settings › Clipboard › Keep: lowering the limit would delete clips, so that asks first; raising it applies at once.
    func setClipboardLimit(_ raw: Int) {
        let n = ClipboardStore.clamp(raw)
        let drop = clipboard.removalCount(at: n)
        guard drop > 0 else { return clipboard.setLimit(n) }
        confirmer.ask(ConfirmRequest(title: "Keep only the last \(n) untagged clips?", command: "Delete the \(drop) oldest untagged clips",
                                     note: "Tagged and pinned clips stay. This can't be undone.", confirmTitle: "Delete \(drop)", danger: true) { [weak self] in
            self?.clipboard.setLimit(n)
        })
    }

    /// Nothing on screen or in flight that a relaunch would interrupt; the updater waits for this before installing.
    var isIdle: Bool {
        !open && !hover && confirmer.pending == nil && emulator.bootingName == nil && emulator.pendingBoot.isEmpty && claudex.busyMember == nil && !calendar.isSigningIn
    }

    func openPanel() {
        if isEnabled(.localIP) { localIP.refresh() }
        open = true
        changed()
    }

    /// Footer "Collapse": closes and unpins.
    func closePanel() {
        clearLeaveTimer()
        open = false
        pinned = false
        hover = false
        settings = false
        claudex.closeDetail()
        clipboard.closeMenus()
        calendar.closeMenus()
        changed()
    }

    /// ⌥Space.
    func togglePanel() {
        open ? closePanel() : openPanel()
    }

    /// ⌘⇧V / ⌘⇧T / ⌘⇧C / ⌘⇧P / ⌘⇧L / ⌘⇧E / ⌘⇧X: opens the panel on `tab` (and Notes sub-tab `sub`). No-op if that menu is switched off.
    func show(_ tab: MainTab, notes sub: NotesTab? = nil) {
        guard isEnabled(tab.feature) else { return }
        if mainTab != tab { setMainTab(tab) }
        if let sub, notesTab != sub { setNotesTab(sub) } // guarded: setNotesTab drops drafts and search
        if open { changed() } else { openPanel() }
    }

    /// A click on the peek's events: the panel opens on My Calendar, jumped to today. The Month / Week / Day choice stays.
    func showToday() {
        calendar.go(.today)
        show(.calendar)
    }

    func togglePin() {
        pinned.toggle()
        changed()
    }

    /// Settings › Appearance: applies everywhere and survives a relaunch.
    func setTheme(_ t: ThemeMode) {
        theme = t
        defaults?.set(t.rawValue, forKey: "theme")
        changed()
    }

    func setPanelSize(_ s: PanelSize) {
        guard s != panelSize else { return }
        shrinking = s == .medium // the container picks its curve from this
        panelSize = s
        defaults?.set(s.rawValue, forKey: "panelSize")
        changed()
    }

    func setTint(_ t: Tint) {
        tint = t
        defaults?.set(t.rawValue, forKey: "tint")
        changed()
    }

    /// Settings › Menus: hides the feature and stops (or restarts) whatever it runs in the background.
    func setEnabled(_ feature: Feature, _ on: Bool) {
        guard on != isEnabled(feature) else { return }
        if on { disabled.remove(feature) } else { disabled.insert(feature) }
        defaults?.set(disabled.map(\.rawValue).sorted(), forKey: "disabledFeatures")
        if !enabledTabs.contains(mainTab), let first = enabledTabs.first { setMainTab(first) }
        applyServices(only: feature)
        changed()
    }

    /// Settings › Peek. claudex on takes the whole hover and switches the others off; claudex off puts them all back on.
    /// The others only change while claudex is off. Today's events are a row under whatever shows, so they change any time
    /// and claudex leaves them as they are.
    func setPeekEnabled(_ source: PeekSource, _ on: Bool) {
        guard on != isPeekEnabled(source) else { return }
        if source.isRow {
            if on { peekOn.insert(source) } else { peekOn.remove(source) }
        } else if source == .claudex {
            peekOn = (on ? [.claudex] : PeekSource.defaultOn).union(peekOn.filter(\.isRow))
        } else {
            guard !isPeekEnabled(.claudex) else { return }
            if on { peekOn.insert(source) } else { peekOn.remove(source) }
        }
        defaults?.set(peekOn.map(\.rawValue).sorted(), forKey: "peekSources")
        if source == .events { loadPeekEvents() } // on: fetch once now, so the first hover already has them; off: the row goes
        changed()
    }

    /// App launch: start the background work of every enabled feature.
    func startServices() { applyServices(only: nil) }

    private func applyServices(only feature: Feature?) {
        func apply(_ f: Feature) -> Bool { feature == nil || feature == f }
        if apply(.clipboard) {
            if isEnabled(.clipboard) { clipboard.startMonitoring() } else { clipboard.stopMonitoring() }
        }
        if apply(.emulator) {
            if isEnabled(.emulator) { emulator.startMonitoring() } else { emulator.stopMonitoring() }
        }
        if apply(.localIP) {
            if isEnabled(.localIP) { localIP.startMonitoring() } else { localIP.stopMonitoring() }
        }
        if apply(.claudex), isEnabled(.claudex) { Task { await claudex.refresh() } }
        if apply(.calendar), !isEnabled(.calendar) { calendar.stop() }
    }

    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
    }

    func toggleSettings() {
        settings.toggle()
        changed()
    }

    /// Settings › Menus: shows or hides the shell on the other displays.
    func setShowOnAllDisplays(_ on: Bool) {
        guard on != showOnAllDisplays else { return }
        showOnAllDisplays = on
        defaults?.set(on, forKey: "showOnAllDisplays")
        changed()
    }

    /// No `changed()`: the window layer calls this from its own sync, and Observation redraws the shells.
    func setActiveDisplay(_ id: DisplayID?) {
        guard id != activeDisplay else { return }
        activeDisplay = id
    }

    func setPeek(_ data: PeekData) {
        peek = data
        peekExtents = PeekMetrics.measure(data)
        changed()
    }

    private func clearLeaveTimer() {
        cancelLeave?()
        cancelLeave = nil
    }

    private func changed() {
        let rank = mode.rank
        if rank != lastRank {
            shrinking = rank < lastRank
            lastRank = rank
        }
        onChange?()
    }
}
