import SwiftUI
import Observation

enum MainTab: String, CaseIterable, Identifiable {
    case notes, claudex, emulator

    var id: String { rawValue }
    var label: String { self == .claudex ? "claudex" : rawValue.capitalized }
    var glyph: Glyph {
        switch self {
        case .notes: .notes
        case .claudex: .gauge
        case .emulator: .phone
        }
    }
    var feature: Feature {
        switch self {
        case .notes: .notes
        case .claudex: .claudex
        case .emulator: .emulator
        }
    }
}

/// What Settings › Menus can switch off. The raw values are stored in UserDefaults.
enum Feature: String, CaseIterable, Identifiable {
    case notes, claudex, emulator, localIP

    var id: String { rawValue }
    var label: String {
        switch self {
        case .notes: "Notes"
        case .claudex: "claudex"
        case .emulator: "Emulator"
        case .localIP: "Local IP"
        }
    }
    var glyph: Glyph {
        switch self {
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
    var mainTab: MainTab = .notes
    var notesTab: NotesTab = .todo
    let notes: NotesStore
    let commands: SnippetStore
    let prompts: SnippetStore
    let confirmer: Confirmer
    let emulator: EmulatorStore
    let claudex: ClaudexStore
    let localIP: LocalIPStore
    /// The user's choice; `resolvedTheme` is what is drawn.
    private(set) var theme: ThemeMode = .dark
    let appearance: AppearanceObserver
    private(set) var tint: Tint = .lime
    /// Settings › Menus: a disabled feature is hidden and runs nothing in the background.
    private(set) var disabled: Set<Feature> = []
    var emulatorTab: EmulatorTab = .devices
    /// Forces the live-activity state (debug menu, snapshots); otherwise it follows the emulator store.
    var bootingOverride: String?
    private(set) var peek = SampleData.peekPool
    private(set) var peekExtents = PeekExtents(left: 0, right: 0)
    /// Hardware notch size in points; nil on a screen without one. Idle is drawn at exactly this size.
    private(set) var notch: CGSize?

    /// Called after every state change so the window layer can update hit-testing and key status.
    @ObservationIgnored var onChange: (() -> Void)?
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
            disabled = Set((defaults.stringArray(forKey: "disabledFeatures") ?? []).compactMap(Feature.init(rawValue:)))
        }
        notes = sample ? .sample() : NotesStore()
        commands = sample ? .sample(.commands) : .persistent(.commands)
        prompts = sample ? .sample(.prompts) : .persistent(.prompts)
        let confirmer = Confirmer()
        self.confirmer = confirmer
        emulator = sample ? EmulatorStore(sample: false, confirmer: confirmer) : EmulatorStore(confirmer: confirmer)
        claudex = sample ? ClaudexStore(sample: true, confirmer: confirmer) : ClaudexStore(confirmer: confirmer)
        localIP = sample ? .sample() : .live()
        if !sample { peek = claudex.peekData } // snapshots keep the prototype's POOL sample
        peekExtents = PeekMetrics.measure(peek)
        claudex.onData = { [weak self] in self?.refreshPeek() }
        if let first = enabledTabs.first, !enabledTabs.contains(mainTab) { mainTab = first }
    }

    /// Re-reads the peek from claudex; only re-measures the ears when something changed.
    func refreshPeek() {
        let data = claudex.peekData
        if data != peek { setPeek(data) }
    }

    // MARK: Derived

    func isEnabled(_ feature: Feature) -> Bool { !disabled.contains(feature) }
    var enabledTabs: [MainTab] { MainTab.allCases.filter { isEnabled($0.feature) } }
    /// claudex off: the peek has no usage to show, so it invites a click instead.
    var peekHint: Bool { !isEnabled(.claudex) }
    private var shownPeekExtents: PeekExtents { peekHint ? PeekMetrics.hintExtents : peekExtents }

    /// Simulator currently booting; drives the live-activity state. Never set while the Emulator menu is off.
    var bootingName: String? { isEnabled(.emulator) ? bootingOverride ?? emulator.bootingName : nil }

    var mode: NotchMode { open ? .open : hover ? .peek : bootingName != nil ? .live : .idle }
    var resolvedTheme: ThemeMode { theme.resolved(systemIsDark: appearance.isDark) }
    var isLight: Bool { resolvedTheme == .light }
    var tokens: Tokens { Tokens(mode: resolvedTheme, tint: tint) }

    var geometry: ShellGeometry {
        switch mode {
        case .idle:
            if let notch {
                ShellGeometry(width: notch.width, height: notch.height,
                              radius: Geo.hardwareNotch.radius, shoulder: Geo.hardwareNotch.shoulder)
            } else {
                ShellGeometry(width: Geo.idle.width, height: Geo.idle.height, radius: Geo.idle.radius)
            }
        case .peek:
            ShellGeometry(width: Geo.keepOutWidth + shownPeekExtents.left + shownPeekExtents.right,
                          height: Geo.peek.height, radius: Geo.peek.radius,
                          centerOffset: (shownPeekExtents.right - shownPeekExtents.left) / 2)
        case .live:
            ShellGeometry(width: Geo.live.width, height: Geo.live.height, radius: Geo.live.radius)
        case .open:
            ShellGeometry(width: Geo.open.width, height: Geo.open.height, radius: Geo.open.radius)
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
            if !hover, isEnabled(.claudex) { Task { await claudex.refresh() } } // reads are cached for 60 s
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
        }
        changed()
    }

    /// Store behind the visible Commands / Prompts sub-tab; nil on TODO and the other main tabs.
    var activeSnippets: SnippetStore? {
        guard mainTab == .notes, isEnabled(.notes) else { return nil }
        switch notesTab {
        case .todo: return nil
        case .commands: return commands
        case .prompts: return prompts
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
        notes.cancelEdit()
        commands.cancelEdit()
        prompts.cancelEdit()
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
        notes.resetTransient()
    }

    /// ⌘F while the panel is key: opens the search of the visible Notes tab (TODO or Prompts).
    func openSearch() {
        guard mainTab == .notes, isEnabled(.notes) else { return }
        switch notesTab {
        case .todo: notes.openSearch()
        case .prompts: prompts.openSearch()
        case .commands: break
        }
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
        changed()
    }

    /// ⌥Space.
    func togglePanel() {
        open ? closePanel() : openPanel()
    }

    /// ⌘⇧V / ⌘⇧E / ⌘⇧X: opens the panel on `tab` (and Notes sub-tab `sub`). No-op if that menu is switched off.
    func show(_ tab: MainTab, notes sub: NotesTab? = nil) {
        guard isEnabled(tab.feature) else { return }
        if mainTab != tab { setMainTab(tab) }
        if let sub, notesTab != sub { setNotesTab(sub) } // guarded: setNotesTab drops drafts and search
        if open { changed() } else { openPanel() }
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

    /// App launch: start the background work of every enabled feature.
    func startServices() { applyServices(only: nil) }

    private func applyServices(only feature: Feature?) {
        func apply(_ f: Feature) -> Bool { feature == nil || feature == f }
        if apply(.emulator) {
            if isEnabled(.emulator) { emulator.startMonitoring() } else { emulator.stopMonitoring() }
        }
        if apply(.localIP) {
            if isEnabled(.localIP) { localIP.startMonitoring() } else { localIP.stopMonitoring() }
        }
        if apply(.claudex), isEnabled(.claudex) { Task { await claudex.refresh() } }
    }

    func toggleSettings() {
        settings.toggle()
        changed()
    }

    func setNotch(_ size: CGSize?) {
        guard size != notch else { return }
        notch = size
        changed()
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
