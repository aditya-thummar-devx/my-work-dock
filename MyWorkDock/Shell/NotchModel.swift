import SwiftUI
import Observation
import UniformTypeIdentifiers

typealias DisplayID = CGDirectDisplayID

enum MainTab: String, CaseIterable, Identifiable {
    case clipboard, calendar, notes, claude, claudex, emulator

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
        case .claude: .chat
        case .notes: .notes
        case .claudex: .gauge
        case .emulator: .phone
        }
    }
    var feature: Feature {
        switch self {
        case .clipboard: .clipboard
        case .calendar: .calendar
        case .claude: .claude
        case .notes: .notes
        case .claudex: .claudex
        case .emulator: .emulator
        }
    }
}

/// What Settings › Menus can switch off. The raw values are stored in UserDefaults.
enum Feature: String, CaseIterable, Identifiable {
    case clipboard, calendar, notes, claude, claudex, emulator, localIP

    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: "Clipboard"
        case .calendar: "My Calendar"
        case .claude: "Claude"
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
        case .claude: .chat
        case .notes: .notes
        case .claudex: .gauge
        case .emulator: .phone
        case .localIP: .wifi
        }
    }
}

/// What Settings › Menus can switch off inside a menu: its sub-tabs. The raw values are stored in UserDefaults.
enum SubMenu: String, CaseIterable, Identifiable {
    case notesTodo, notesCommands, notesPrompts, notesLinks
    case emulatorDevices, emulatorWireless, emulatorTunnel
    case claudeAgents, claudeSessions, claudeTokens
    case claudexUsage, claudexPool, claudexPlay, claudexHealth

    // The raw value is the menu plus the tab's own raw value, so one rule covers every tab (NotchModelTests checks it).
    init(_ tab: NotesTab) { self = SubMenu(rawValue: "notes" + tab.rawValue.capitalized)! }
    init(_ tab: EmulatorTab) { self = SubMenu(rawValue: "emulator" + tab.rawValue.capitalized)! }
    init(_ tab: ClaudeTab) { self = SubMenu(rawValue: "claude" + tab.rawValue.capitalized)! }
    init(_ tab: ClaudexTab) { self = SubMenu(rawValue: "claudex" + tab.rawValue.capitalized)! }

    var id: String { rawValue }
    var parent: Feature {
        switch self {
        case .notesTodo, .notesCommands, .notesPrompts, .notesLinks: .notes
        case .emulatorDevices, .emulatorWireless, .emulatorTunnel: .emulator
        case .claudeAgents, .claudeSessions, .claudeTokens: .claude
        case .claudexUsage, .claudexPool, .claudexPlay, .claudexHealth: .claudex
        }
    }
    /// The sub-tab's name, as the menu shows it.
    var label: String {
        switch self {
        case .notesTodo: "TODO"
        case .notesCommands: "Commands"
        case .notesPrompts: "Prompts"
        case .notesLinks: "Links"
        case .emulatorDevices: "Devices"
        case .emulatorWireless: "Wireless"
        case .emulatorTunnel: "Tunnel"
        case .claudeAgents: "Agents"
        case .claudeSessions: "Sessions"
        case .claudeTokens: "Tokens & cost"
        case .claudexUsage: "Usage"
        case .claudexPool: "Pool"
        case .claudexPlay: "Playground"
        case .claudexHealth: "Health"
        }
    }
}

/// Where the dock shell sits on screen. Raw values are stored in UserDefaults.
enum NotchPosition: String, CaseIterable, Identifiable {
    case top           // default — sits over the hardware notch / top-centre
    case bottomLeft    // corner anchor, bottom-left of the screen
    case bottomRight   // corner anchor, bottom-right of the screen

    var id: String { rawValue }
    var label: String {
        switch self {
        case .top:         "Top (notch)"
        case .bottomLeft:  "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Everything the shell animates: size, bottom radius and horizontal offset from the hardware-notch centre.
/// Which corner (bottom-left or bottom-right) anchors a corner-mode shell; nil means top-centre (default).
enum CornerAnchor: Equatable { case bottomLeft, bottomRight }

struct ShellGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var centerOffset: CGFloat = 0
    var shoulder: CGFloat = Geo.shoulder
    var cornerAnchor: CornerAnchor? = nil
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
    /// Claude's sub-tab; it stays where it was when you leave the menu and come back.
    var claudeTab: ClaudeTab = .agents
    /// Claude › Refresh is running.
    private(set) var claudeRefreshing = false
    /// When Claude › Refresh last finished, for "Updated just now".
    private(set) var claudeRefreshedAt: Date?
    let clipboard: ClipboardStore
    let notes: NotesStore
    /// Claude Code adds todos through it (`mwd-mcp`); runs while Notes › TODO is on.
    let todoBridge: TodoBridge
    let commands: SnippetStore
    let prompts: SnippetStore
    let links: SnippetStore
    let confirmer: Confirmer
    /// Notes › Commands › Run: one command at a time, its output in a sheet over the panel.
    let runner: CommandRunner
    let emulator: EmulatorStore
    let claudex: ClaudexStore
    let claudeUsage: ClaudeUsageStore
    let localIP: LocalIPStore
    let calendar: CalendarStore
    let agents: AgentStore
    let sessions: SessionsStore
    /// Settings › Shortcuts: global hotkeys and their custom bindings.
    let shortcuts: ShortcutStore
    /// Settings › Appearance › Notch buddy › Custom: the Lottie files the user added.
    let customBuddies: CustomBuddyStore
    /// The user's choice; `resolvedTheme` is what is drawn.
    private(set) var theme: ThemeMode = .dark
    let appearance: AppearanceObserver
    private(set) var tint: Tint = .lime
    /// Settings › Appearance: size of the open panel.
    private(set) var panelSize: PanelSize = .medium
    /// Settings › Menus: a disabled feature is hidden and runs nothing in the background.
    private(set) var disabled: Set<Feature> = []
    /// Settings › Menus › a menu's sub-tabs: a switched-off one is hidden in its menu. Kept while the menu itself is off.
    private(set) var disabledSubs: Set<SubMenu> = []
    /// Settings › Peek: the sources hover shows. `[.claudex]` alone, or any of the others (claudex takes the whole hover).
    private(set) var peekOn: Set<PeekSource> = PeekSource.defaultOn
    /// Settings › Peek › Calendar meeting peek: auto-opens the notch N minutes before a meeting with a video link.
    private(set) var calendarAutoPeekEnabled = false
    /// How many minutes before start the heads-up fires. Range 2…30; default 5.
    private(set) var calendarAutoPeekThreshold = 5
    /// The active auto-peek state; nil when no event is being tracked.
    private(set) var calendarPeekState: CalendarPeekState?
    @ObservationIgnored private var autoPeekScheduler: CalendarAutoPeekScheduler?
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
    /// Settings › Appearance › Notch buddy.
    private(set) var buddy = BuddyPrefs()
    /// Settings › Appearance › Notch position: where on screen the shell sits.
    private(set) var notchPosition: NotchPosition = .top
    /// The first-launch hint ("I live in your notch. Hover me.") ends for good at the first hover or open.
    private(set) var buddyHintSeen = false
    /// Displays with no menu bar showing (a full-screen app, or an auto-hidden menu bar): the buddy hides on them while
    /// `buddy.hideInFullScreen` is on. Fed by the window layer.
    private(set) var menuBarHidden: Set<DisplayID> = []
    /// False while the display sleeps or the session is switched out: the buddy stops moving.
    private(set) var screenAwake = true
    /// True while Mission Control (or Show Desktop / Exposé) is active: all notch panels hide until it exits.
    private(set) var missionControlActive = false
    /// The last hover or panel open (or the launch): a custom buddy naps `Geo.Buddy.States.napAfter` after it.
    private(set) var lastActive = Date()
    /// Settings › Version: "1.0 (1)", and when this version first ran here (an install or an update). nil in snapshots and tests.
    let version = NotchModel.versionLabel
    private(set) var updatedAt: Date?
    /// Settings › Version: whether updates are checked automatically in the background. Defaults to true.
    private(set) var autoCheckUpdates = true
    @ObservationIgnored var onAutoCheckUpdates: ((Bool) -> Void)?
    /// Display whose shell peeks / opens; the others stay idle. nil (snapshots) = every shell follows `mode`.
    private(set) var activeDisplay: DisplayID?

    /// Called after every state change so the window layer can update hit-testing and key status.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when shortcuts or feature availability changes so registered hotkeys can re-sync.
    @ObservationIgnored var onShortcutsChange: (() -> Void)?
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
    /// The folder picker for a Run is open.
    private(set) var picking = false
    /// Asks for a folder, opening at `start` when given; nil when cancelled. Injected by tests.
    @ObservationIgnored var pickFolder: (URL?) async -> URL? = NotchModel.chooseFolder
    /// Asks for a custom buddy's Lottie file; nil when cancelled. Injected by tests.
    @ObservationIgnored var pickBuddyFile: () async -> URL? = NotchModel.chooseBuddyFile
    /// Touch ID / password prompt for an unlock is open.
    private(set) var authenticating = false
    /// Why this Mac cannot check its owner, nil when it can; the prompt itself. Injected by tests.
    @ObservationIgnored var authUnavailable: () -> String? = Authenticator.unavailableReason
    @ObservationIgnored var authenticate: (String) async -> Bool = { await Authenticator.authenticate(reason: $0) }
    @ObservationIgnored private var lastRank = NotchMode.idle.rank
    /// Ids of the requests waiting on the last Agents update, to tell a new one from one already shown.
    @ObservationIgnored private var seenRequests: Set<String> = []

    /// `sample: true` keeps every store in memory with the designs' sample data (snapshots, tests).
    @ObservationIgnored private let defaults: UserDefaults?

    init(sample: Bool = false, customBuddies: CustomBuddyStore? = nil) {
        defaults = sample ? nil : .standard
        appearance = sample ? AppearanceObserver(isDark: true) : .live()
        if let defaults {
            theme = defaults.string(forKey: "theme").flatMap(ThemeMode.init(rawValue:)) ?? .system
            tint = defaults.string(forKey: "tint").flatMap(Tint.init(rawValue:)) ?? .lime
            panelSize = defaults.string(forKey: "panelSize").flatMap(PanelSize.init(rawValue:)) ?? .medium
            let saved = Self.migrated(features: defaults.stringArray(forKey: "disabledFeatures") ?? [],
                                      subs: defaults.stringArray(forKey: "disabledSubMenus") ?? [])
            disabled = Set(saved.features.compactMap(Feature.init(rawValue:)))
            disabledSubs = Set(saved.subs.compactMap(SubMenu.init(rawValue:)))
            defaults.set(saved.features.filter { Feature(rawValue: $0) != nil }.sorted(), forKey: "disabledFeatures")
            defaults.set(saved.subs.filter { SubMenu(rawValue: $0) != nil }.sorted(), forKey: "disabledSubMenus")
            if let saved = defaults.stringArray(forKey: "peekSources") { peekOn = PeekSource.restored(saved) }
            showOnAllDisplays = defaults.bool(forKey: "showOnAllDisplays")
            calendarAutoPeekEnabled = defaults.bool(forKey: "calendarAutoPeekEnabled")
            let savedThreshold = defaults.integer(forKey: "calendarAutoPeekThreshold")
            calendarAutoPeekThreshold = savedThreshold > 0 ? min(30, max(2, savedThreshold)) : 5
            buddy = BuddyPrefs(defaults: defaults)
            buddyHintSeen = defaults.bool(forKey: "buddyHintSeen")
            if defaults.string(forKey: "seenVersion") != version {
                defaults.set(version, forKey: "seenVersion")
                defaults.set(Date(), forKey: "updatedAt")
            }
            updatedAt = defaults.object(forKey: "updatedAt") as? Date
            autoCheckUpdates = defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true
            notchPosition = defaults.string(forKey: "notchPosition").flatMap(NotchPosition.init(rawValue:)) ?? .top
        } else {
            buddyHintSeen = true // snapshots and tests start without the hint; the buddy states ask for it
        }
        let confirmer = Confirmer()
        self.confirmer = confirmer
        clipboard = sample ? .sample(confirmer: confirmer) : .live(confirmer: confirmer)
        notes = sample ? .sample() : NotesStore()
        todoBridge = sample ? .sample(notes: notes) : .live(notes: notes)
        commands = sample ? .sample(.commands) : .persistent(.commands)
        prompts = sample ? .sample(.prompts) : .persistent(.prompts)
        links = sample ? .sample(.links) : .persistent(.links)
        runner = CommandRunner()
        emulator = sample ? EmulatorStore(sample: false, confirmer: confirmer) : EmulatorStore(confirmer: confirmer)
        claudex = sample ? ClaudexStore(sample: true, confirmer: confirmer) : ClaudexStore(confirmer: confirmer)
        claudeUsage = sample ? ClaudeUsageStore(sample: true) : ClaudeUsageStore()
        localIP = sample ? .sample() : .live()
        calendar = sample ? .sample() : .live(confirmer: confirmer)
        agents = sample ? .sample() : .live()
        sessions = sample ? .sample() : .live()
        shortcuts = ShortcutStore(defaults: sample ? nil : .standard)
        self.customBuddies = customBuddies ?? (sample ? .sample() : .live())
        if !sample { peek = claudex.peekData } // snapshots keep the prototype's POOL sample
        peekExtents = PeekMetrics.measure(peek)
        claudex.onData = { [weak self] in self?.refreshPeek() }
        clipboard.onCopied = { [weak self] in self?.closePanel() }
        commands.onCopied = { [weak self] in self?.closePanel() }
        prompts.onCopied = { [weak self] in self?.closePanel() }
        links.onCopied = { [weak self] in self?.closePanel() }
        notes.onCopied = { [weak self] in self?.closePanel() }
        calendar.willOpenBrowser = { [weak self] in self?.closePanel() } // the open panel floats above the browser
        calendar.onSignedIn = { [weak self] in
            self?.show(.calendar)
            self?.applyCalendarAutoPeek()
        }
        agents.onData = { [weak self] in
            guard let self else { return }
            self.sessions.ensureTitles(self.agents.sessions.map(\.transcriptID))
            self.showNewRequests()
        }
        shortcuts.onChange = { [weak self] in
            self?.onShortcutsChange?()
            self?.changed()
        }
        if let first = enabledTabs.first, !enabledTabs.contains(mainTab) { mainTab = first }
        syncSubMenus()
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
            let rows = upcoming.prefix(Geo.Peek.eventsShown).map(PeekEvent.init)
            next = PeekEvents(rows: rows, more: upcoming.count - rows.count, now: calendar.now())
        }
        guard next != peekEvents else { return }
        peekEvents = next
        changed()
    }

    // MARK: Derived

    func isEnabled(_ feature: Feature) -> Bool { !disabled.contains(feature) }
    var enabledTabs: [MainTab] { MainTab.allCases.filter { isEnabled($0.feature) } }
    /// The stored choice for one sub-tab; whether it shows also depends on its menu being on.
    func isEnabled(_ sub: SubMenu) -> Bool { !disabledSubs.contains(sub) }
    var enabledNotesTabs: [NotesTab] { NotesTab.allCases.filter { isEnabled(SubMenu($0)) } }
    var enabledEmulatorTabs: [EmulatorTab] { EmulatorTab.allCases.filter { isEnabled(SubMenu($0)) } }
    var enabledClaudeTabs: [ClaudeTab] { ClaudeTab.allCases.filter { isEnabled(SubMenu($0)) } }
    func isPeekEnabled(_ source: PeekSource) -> Bool { peekOn.contains(source) }

    /// What hover draws. claudex on: its two ears, or the hint while it has no account to show. Otherwise the TODO and
    /// clipboard counts (left) and the Local IP (right), each only when its source is on, its menu is on and it has
    /// something to show; with none of them, the hint invites a click.
    var peekContent: PeekContent {
        func shows(_ source: PeekSource) -> Bool {
            isPeekEnabled(source) && isEnabled(source.feature) && (source.subMenu.map(isEnabled) ?? true)
        }
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

    var mode: NotchMode { open ? .open : (hover || calendarPeekState != nil) ? .peek : bootingName != nil ? .live : .idle }
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
        let m = mode(on: display)
        switch notchPosition {
        case .top:
            switch m {
            case .idle:
                return idleGeometry(notch: notch, on: display)
            case .peek:
                // Calendar auto-peek: uses a fixed wide bar matching the design (610 pt from HTML spec)
                // or shrunk width (300 pt) when in shrunk state and not re-expanded.
                if let calPeek = calendarPeekState {
                    if calPeek.isShrunk && !calPeek.isVisible {
                        return ShellGeometry(width: Geo.calendarPeekShrunk.width, height: Geo.calendarPeekShrunk.height, radius: Geo.calendarPeekShrunk.radius)
                    }
                    return ShellGeometry(width: Geo.calendarPeek.width, height: Geo.peek.height, radius: Geo.peek.radius)
                }
                // The events row hangs under the ears: the shell grows by its height and is wide enough for a title. The extra width is
                // split evenly, so the ears stay where they were against the notch.
                return ShellGeometry(width: max(Geo.keepOutWidth + shownPeekExtents.left + shownPeekExtents.right, peekEvents == nil ? 0 : Geo.Peek.eventsMinWidth),
                                     height: Geo.peek.height + (peekEvents?.height ?? 0), radius: Geo.peek.radius,
                                     centerOffset: (shownPeekExtents.right - shownPeekExtents.left) / 2)
            case .live:
                return ShellGeometry(width: Geo.live.width, height: Geo.live.height, radius: Geo.live.radius)
            case .open:
                return ShellGeometry(width: panelSize.size(on: screen).width, height: panelSize.size(on: screen).height, radius: Geo.open.radius)
            }
        case .bottomLeft:
            return cornerGeometry(anchor: .bottomLeft, mode: m, screen: screen)
        case .bottomRight:
            return cornerGeometry(anchor: .bottomRight, mode: m, screen: screen)
        }
    }

    /// Shell geometry when the dock lives in a bottom corner.
    private func cornerGeometry(anchor: CornerAnchor, mode: NotchMode, screen: CGSize?) -> ShellGeometry {
        switch mode {
        case .idle:
            return ShellGeometry(width: Geo.Corner.idle.size, height: Geo.Corner.idle.size,
                                 radius: Geo.Corner.idle.radius, shoulder: 0, cornerAnchor: anchor)
        case .peek:
            if let calPeek = calendarPeekState {
                if calPeek.isShrunk && !calPeek.isVisible {
                    return ShellGeometry(width: Geo.calendarPeekShrunk.width, height: Geo.calendarPeekShrunk.height,
                                         radius: Geo.calendarPeekShrunk.radius, shoulder: 0, cornerAnchor: anchor)
                }
                return ShellGeometry(width: Geo.calendarPeek.width, height: Geo.peek.height,
                                     radius: Geo.peek.radius, shoulder: 0, cornerAnchor: anchor)
            }
            return ShellGeometry(width: max(Geo.keepOutWidth + shownPeekExtents.left + shownPeekExtents.right, peekEvents == nil ? 0 : Geo.Peek.eventsMinWidth),
                                 height: Geo.peek.height + (peekEvents?.height ?? 0), radius: Geo.peek.radius,
                                 shoulder: 0, cornerAnchor: anchor)
        case .live:
            // Live activity bar appears in the corner (same bar, anchored to corner edge)
            return ShellGeometry(width: Geo.live.width, height: Geo.live.height,
                                 radius: Geo.live.radius, shoulder: 0, cornerAnchor: anchor)
        case .open:
            let sz = panelSize.size(on: screen)
            return ShellGeometry(width: sz.width, height: sz.height,
                                 radius: Geo.open.radius, shoulder: 0, cornerAnchor: anchor)
        }
    }

    /// The idle shell, whatever the mode is now (the window layer asks while a peek is open): the hardware notch's own size (a pill
    /// without one). With the buddy wanted the shell grows by its ear on the right, and moves half of that over, so the left edge
    /// stays on the hardware's.
    func idleGeometry(notch: CGSize?, on display: DisplayID?) -> ShellGeometry {
        var g = notch.map(Geo.hardwareNotchShell) ?? ShellGeometry(width: Geo.idle.width, height: Geo.idle.height, radius: Geo.idle.radius)
        if buddyWanted(on: display) {
            g.width += Geo.Buddy.ear
            g.centerOffset = Geo.Buddy.ear / 2
        }
        return g
    }

    /// The buddy would sit on `display`'s idle notch/corner: it is on, and no full-screen app has taken the menu bar there.
    private func buddyWanted(on display: DisplayID?) -> Bool {
        buddy.on && !(buddy.hideInFullScreen && display.map(menuBarHidden.contains) == true)
    }

    /// What the buddy plays: the style Settings picked, through the library for a custom one.
    var buddyAsset: BuddyAsset { BuddyAsset(buddy, library: customBuddies) }
    /// The same with a custom buddy's glance, nap and offsets.
    var buddySet: BuddySet { BuddySet(buddy, library: customBuddies) }

    /// The buddy is drawn on `display`'s idle shell: wanted there, and nothing else is showing.
    func buddyShown(on display: DisplayID? = nil) -> Bool { buddyWanted(on: display) && mode(on: display) == .idle }

    /// The first-launch hint hangs under the buddy that sits on the display the pointer is on (any, in snapshots).
    func hintShown(on display: DisplayID? = nil) -> Bool {
        !buddyHintSeen && buddyShown(on: display) && (display == nil || activeDisplay == nil || display == activeDisplay)
    }

    // MARK: Pointer

    /// Fed by the window layer on every mouse move with "is the pointer over the shape".
    /// Leaving arms the 350 ms timer once; re-entering cancels it. A panel opened by keyboard never
    /// arms it until the pointer has entered at least once (`hover` stays false).
    func pointer(inside: Bool) {
        if inside {
            if let state = calendarPeekState, state.isShrunk {
                autoPeekScheduler?.setReExpanded(true, currentState: state)
            }
            guard !hover || cancelLeave != nil else { return }
            clearLeaveTimer()
            if !hover, isPeekEnabled(.claudex), isEnabled(.claudex) { Task { await claudex.refresh() } } // reads are cached for 60 s
            if !hover {
                loadPeekEvents()
                endBuddyHint()
                lastActive = Date()
            }
            hover = true
            changed()
        } else if hover, cancelLeave == nil {
            cancelLeave = schedule(Geo.leaveDelay) { [weak self] in self?.leaveFired() }
        }
    }

    private func leaveFired() {
        cancelLeave = nil
        if let state = calendarPeekState, case .shrunk(let item, true) = state {
            autoPeekScheduler?.setReExpanded(false, currentState: state)
        }
        // The folder picker, its confirm sheet and the run sheet all lead the pointer away from the panel; none of them may vanish under it.
        if picking || authenticating || runner.sheetOpen || confirmer.pending?.keepPanelOpen == true { return }
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
        settings = false // the settings screen takes the content area, so picking a menu leaves it
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

    /// Shift+Tab: next sub-tab of the visible main menu, wrapping. Sub-tabs switched off in Settings are skipped.
    func cycleInnerTab() {
        guard !settings, isEnabled(mainTab.feature) else { return }
        func next<T: Equatable>(_ v: T, in shown: [T]) -> T? {
            guard shown.count > 1 else { return nil }
            return shown[((shown.firstIndex(of: v) ?? -1) + 1) % shown.count]
        }
        switch mainTab {
        case .clipboard: break
        case .calendar: calendar.cycleMode()
        case .claude: if let tab = next(claudeTab, in: enabledClaudeTabs) { setClaudeTab(tab) }
        case .notes: if let tab = next(notesTab, in: enabledNotesTabs) { setNotesTab(tab) }
        case .claudex: if let tab = next(claudex.activeTab, in: claudex.visibleTabs) { claudex.select(tab) }
        case .emulator: if let tab = next(emulatorTab, in: enabledEmulatorTabs) { setEmulatorTab(tab) }
        }
    }

    /// Agents › Show on board.
    func showOnBoard(_ transcriptID: String) {
        guard isEnabled(.claude), enabledClaudeTabs.contains(.sessions) else { return }
        setMainTab(.claude)
        claudeTab = .sessions
        sessions.focus(transcriptID)
    }

    func setClaudeTab(_ tab: ClaudeTab) { claudeTab = tab }

    /// A request that was not waiting a moment ago, while Claude is on screen on another tab: Agents is where it is answered.
    private func showNewRequests() {
        let ids = Set(agents.pending.map(\.id))
        defer { seenRequests = ids }
        guard !ids.subtracting(seenRequests).isEmpty, open, !settings, mainTab == .claude, claudeTab != .agents,
              enabledClaudeTabs.contains(.agents) else { return }
        claudeTab = .agents
        changed()
    }

    /// Claude › Refresh: sessions, the agents' hook setup and Tokens & cost, all at once.
    func refreshClaude() async {
        guard !claudeRefreshing else { return }
        claudeRefreshing = true
        defer { claudeRefreshing = false }
        // Tabs switched off in Settings › Menus stay off: no transcript scan for a hidden Tokens & cost.
        let tabs = enabledClaudeTabs
        async let board: Void = tabs.contains(.sessions) ? sessions.refresh(fresh: true) : ()
        async let live: Void = tabs.contains(.agents) ? agents.refresh() : ()
        async let usage: Void = tabs.contains(.tokens) ? claudeUsage.refresh() : ()
        async let seen: Void = Self.pause(0.6) // long enough to see the spinner when everything is already current
        _ = await (board, live, usage, seen)
        sessions.ensureTitles(agents.sessions.map(\.transcriptID))
        claudeRefreshedAt = Date()
    }

    private static func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// "just now" / "42s ago" / "3m ago" after Claude › Refresh; empty before the first one.
    var claudeFreshLabel: String {
        guard let at = claudeRefreshedAt else { return "" }
        let age = Int(Date().timeIntervalSince(at))
        return "Updated " + (age < 5 ? "just now" : age < 60 ? "\(age)s ago" : "\(age / 60)m ago")
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

    /// Notes › Commands › Run: use the command's saved folder or pick one (saved for next time), confirm, then run and show the output.
    /// Cancelling either step runs nothing.
    func runCommand(_ id: Int) {
        guard let text = commands.items.first(where: { $0.id == id })?.text,
              !picking, !runner.isRunning, runner.availability(of: text) == .ready || runner.availability(of: text) == .unlocked else { return }
        if let saved = commands.folder(id) { confirmRun(text, in: saved) } else { pick(for: id, from: nil) { [self] in confirmRun(text, in: $0) } }
    }

    /// The folder chip: pick another folder for this command. Does not run it.
    func changeCommandFolder(_ id: Int) {
        guard !picking, !runner.isRunning else { return }
        pick(for: id, from: commands.folder(id)) { _ in }
    }

    private func confirmRun(_ text: String, in folder: URL) {
        confirmer.ask(ConfirmRequest(title: "Run this command?", command: "cd \(Self.shellQuoted(folder.path)) && \(text)",
                                     note: "Runs in \(folder.path). Stop ends it.", confirmTitle: "Run",
                                     commandLines: 4, keepPanelOpen: true) { [runner] in
            runner.start(command: text, in: folder)
        })
    }

    /// Opens the picker at `start` (the panel stays open meanwhile), remembers the choice on the command, then calls `then`. Cancelling does neither.
    private func pick(for id: Int, from start: URL?, then: @escaping (URL) -> Void) {
        picking = true
        Task {
            let folder = await pickFolder(start)
            picking = false
            changed() // the picker took key status; the panel takes it back for the confirm sheet
            guard let folder else { return }
            commands.setFolder(id, folder.path)
            then(folder)
        }
    }

    /// Click on a blocked command's lock: confirm, then the Mac's owner check; only then is that exact text runnable.
    /// A cancel, a failure or a Mac that cannot check its owner leaves it locked.
    func unlockCommand(_ id: Int) {
        guard let text = commands.items.first(where: { $0.id == id })?.text, !authenticating,
              let why = CommandSafety.blockedReason(text), !runner.unlocked.contains(text) else { return }
        if let unavailable = authUnavailable() {
            runner.unlockUnavailable = unavailable
            return
        }
        runner.unlockUnavailable = nil
        confirmer.ask(ConfirmRequest(title: "Unlock this command?", command: text, note: "Blocked: \(why). Needs Touch ID or your password.",
                                     confirmTitle: "Unlock", danger: true, commandLines: 4, keepPanelOpen: true) { [weak self] in
            guard let self else { return }
            authenticating = true
            let ok = await authenticate("Unlock a blocked command in MyWorkDock")
            authenticating = false
            if ok { runner.unlock(text) }
            changed() // the prompt took key status; the panel takes it back
        })
    }

    static func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// One-folder picker, opened at `start` when the command already has a folder. The panel floats at status-bar level, so the picker goes one above it.
    static func chooseFolder(from start: URL?) async -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        panel.prompt = start == nil ? "Run Here" : "Choose"
        panel.message = "Choose the folder to run the command in"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        return await withCheckedContinuation { cont in
            panel.begin { cont.resume(returning: $0 == .OK ? panel.url : nil) }
        }
    }

    /// One Lottie file (`.json`, the only kind a buddy can be). Same level as the folder picker, for the same reason; the message says
    /// what the check will ask of it.
    static func chooseBuddyFile() async -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Buddy"
        panel.message = BuddyFileCheck.Limits.summary
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        return await withCheckedContinuation { cont in
            panel.begin { cont.resume(returning: $0 == .OK ? panel.url : nil) }
        }
    }

    /// Nothing on screen or in flight that a relaunch would interrupt; the updater waits for this before installing.
    var isIdle: Bool {
        !open && !hover && confirmer.pending == nil && emulator.bootingName == nil && emulator.pendingBoot.isEmpty && claudex.busyMember == nil && !calendar.isSigningIn
            && !runner.isRunning
    }

    func openPanel() {
        if isEnabled(.localIP) { localIP.refresh() }
        endBuddyHint()
        lastActive = Date()
        open = true
        changed()
    }

    /// Whether any modal sheet, confirmation popup, or dropdown menu is currently visible over the panel.
    var hasOpenPopup: Bool {
        confirmer.pending != nil
            || calendar.selected != nil
            || claudex.detailName != nil
            || runner.sheetOpen
            || calendar.calendarsMenuOpen
            || clipboard.tagMenuOpen
            || notes.tagMenuOpen || notes.filterMenuOpen || notes.editTagMenuOpen || notes.tagManageOpen || notes.tagFormOpen
            || claudex.sortOpen
            || emulator.targetMenuOpen
    }

    /// Esc key: cancels or closes any open popup, sheet, or menu first, keeping the panel open.
    /// Closes the panel only when no popup is open (or shrinks calendar peek if active).
    func handleEscape() {
        if calendarPeekState != nil && !open {
            shrinkCalendarPeek()
            return
        }

        if confirmer.pending != nil {
            confirmer.cancel()
            changed()
            return
        }

        if calendar.selected != nil {
            calendar.closeDetail()
            changed()
            return
        }

        if claudex.detailName != nil {
            claudex.closeDetail()
            changed()
            return
        }

        if runner.sheetOpen {
            runner.dismiss()
            changed()
            return
        }

        if calendar.calendarsMenuOpen {
            calendar.calendarsMenuOpen = false
            changed()
            return
        }

        if clipboard.tagMenuOpen {
            clipboard.closeMenus()
            changed()
            return
        }

        if notes.tagMenuOpen || notes.filterMenuOpen || notes.editTagMenuOpen || notes.tagManageOpen || notes.tagFormOpen {
            notes.closeMenus()
            changed()
            return
        }

        if claudex.sortOpen {
            claudex.sortOpen = false
            changed()
            return
        }

        if emulator.targetMenuOpen {
            emulator.targetMenuOpen = false
            changed()
            return
        }

        if mainTab == .clipboard && clipboard.searchOpen {
            clipboard.closeSearch()
            changed()
            return
        }

        if mainTab == .notes && notesTab == .todo && notes.searchOpen {
            notes.closeSearch()
            changed()
            return
        }

        if mainTab == .notes, let active = activeSnippets, active.searchOpen {
            active.closeSearch()
            changed()
            return
        }

        closePanel()
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

    /// ⌘⇧V / ⌘⇧M / ⌘⇧G / ⌘⇧D / ⌘⇧C / ⌘⇧P / ⌘⇧L / ⌘⇧E / ⌘⇧X: opens the panel on `tab` (and Notes sub-tab `sub`). No-op if that menu is switched off;
    /// a Notes sub-tab that is switched off leaves Notes on the tab it was on.
    func show(_ tab: MainTab, notes sub: NotesTab? = nil) {
        guard isEnabled(tab.feature) else { return }
        settings = false
        if mainTab != tab { setMainTab(tab) }
        if let sub, notesTab != sub, enabledNotesTabs.contains(sub) { setNotesTab(sub) } // guarded: setNotesTab drops drafts and search
        if open { changed() } else { openPanel() }
    }

    /// A click on the peek's events (not on one of them): the panel opens on My Calendar, jumped to today. The Month / Week / Day
    /// choice stays.
    func showToday() {
        calendar.go(.today)
        show(.calendar)
    }

    /// A click on one event in the peek: the panel opens on My Calendar at that event, scrolled to it, with its sheet open, as if it
    /// had been clicked in the grid. The tab is shown first: switching to it closes the calendar's sheet.
    func showEvent(_ event: CalendarEvent) {
        show(.calendar)
        calendar.reveal(event, on: calendar.now())
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

    /// Settings › Appearance › Notch buddy: applies at once (the idle shell grows or shrinks by the ear) and survives a relaunch.
    func setBuddy(_ prefs: BuddyPrefs) {
        guard prefs != buddy else { return }
        buddy = prefs
        if let defaults { prefs.save(to: defaults) }
        changed()
    }

    /// Settings › Notch buddy › +: asks for a Lottie file (the panel stays open meanwhile), checks it, keeps it and shows it. A file that
    /// is turned down changes nothing; the library says why.
    func addCustomBuddy() {
        guard !picking else { return }
        picking = true
        Task {
            let file = await pickBuddyFile()
            picking = false
            changed() // the picker took key status; the panel takes it back
            guard let file, let id = customBuddies.add(from: file) else { return }
            var next = buddy
            next.style = .custom
            next.custom = id
            setBuddy(next)
        }
    }

    /// Deletes a custom buddy. If it was the one showing, the newest one left takes over, or the face when there is none.
    func removeCustomBuddy(_ id: String) {
        customBuddies.remove(id)
        guard buddy.custom == id else { return }
        var next = buddy
        next.custom = customBuddies.entries.last?.id
        if next.custom == nil, next.style == .custom { next.style = .face }
        setBuddy(next)
    }

    /// Settings › Notch buddy › a custom buddy's Idle, Every ~45 s or After 10 min file: asks for a Lottie file (the panel stays open
    /// meanwhile), checks it and puts it in that buddy's set. A file that is turned down changes nothing; the library says why.
    func setCustomBuddyFile(_ state: BuddyState, of id: String) {
        guard !picking else { return }
        picking = true
        Task {
            let file = await pickBuddyFile()
            picking = false
            changed()
            guard let file else { return }
            customBuddies.setFile(state, of: id, from: file)
        }
    }

    /// The window layer: which displays have no menu bar showing right now.
    func setMenuBarHidden(_ displays: Set<DisplayID>) {
        guard displays != menuBarHidden else { return }
        menuBarHidden = displays
        changed()
    }

    /// No `changed()`: only the buddy reads it, and Observation redraws that.
    func setScreenAwake(_ awake: Bool) { screenAwake = awake }

    /// The window layer: Mission Control (or Show Desktop) just became active or exited.
    func setMissionControlActive(_ active: Bool) {
        guard active != missionControlActive else { return }
        missionControlActive = active
        changed()
    }

    /// The first hover or open ends the hint for good. Only while the buddy is on: one that was never shown has not said hello.
    private func endBuddyHint() {
        guard buddy.on, !buddyHintSeen else { return }
        buddyHintSeen = true
        defaults?.set(true, forKey: "buddyHintSeen")
    }

    /// DEBUG menu and snapshots: say hello again.
    func resetBuddyHint() {
        buddyHintSeen = false
        defaults?.set(false, forKey: "buddyHintSeen")
        changed()
    }

    /// Settings › Menus: hides the feature and stops (or restarts) whatever it runs in the background.
    func setEnabled(_ feature: Feature, _ on: Bool) {
        guard on != isEnabled(feature) else { return }
        if on { disabled.remove(feature) } else { disabled.insert(feature) }
        defaults?.set(disabled.map(\.rawValue).sorted(), forKey: "disabledFeatures")
        if !enabledTabs.contains(mainTab), let first = enabledTabs.first {
            let inSettings = settings // switched off from the settings screen: stay there
            setMainTab(first)
            settings = inSettings
        }
        applyServices(only: feature)
        onShortcutsChange?()
        changed()
    }

    /// Settings › Menus › a menu's sub-tabs: hides or shows one. The last one showing cannot go off, so a menu is never empty;
    /// the tab on screen moves to the first one left.
    func setEnabled(_ sub: SubMenu, _ on: Bool) {
        guard on != isEnabled(sub) else { return }
        if on {
            disabledSubs.remove(sub)
        } else {
            guard SubMenu.allCases.contains(where: { $0.parent == sub.parent && $0 != sub && isEnabled($0) }) else { return }
            disabledSubs.insert(sub)
        }
        defaults?.set(disabledSubs.map(\.rawValue).sorted(), forKey: "disabledSubMenus")
        syncSubMenus()
        if sub.parent == .claude { applyServices(only: .claude) } // the hook server and the transcript scan follow their tabs
        if sub == .notesTodo { applyServices(only: .notes) } // so does the todo socket
        onShortcutsChange?()
        changed()
    }

    /// Hidden sub-tabs reach the screens, and a tab that is now hidden gives way to the first one showing.
    private func syncSubMenus() {
        claudex.hidden = Set(ClaudexTab.allCases.filter { !isEnabled(SubMenu($0)) })
        if let first = enabledNotesTabs.first, !enabledNotesTabs.contains(notesTab) { setNotesTab(first) }
        if let first = enabledEmulatorTabs.first, !enabledEmulatorTabs.contains(emulatorTab) { setEmulatorTab(first) }
        if let first = enabledClaudeTabs.first, !enabledClaudeTabs.contains(claudeTab) { setClaudeTab(first) }
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

    /// Settings › Peek › Calendar meeting heads-up auto-peek toggle.
    func setCalendarAutoPeekEnabled(_ on: Bool) {
        guard on != calendarAutoPeekEnabled else { return }
        calendarAutoPeekEnabled = on
        defaults?.set(on, forKey: "calendarAutoPeekEnabled")
        applyCalendarAutoPeek()
        changed()
    }

    /// Settings › Peek › Minutes before meeting to show heads-up (2…30 min).
    func setCalendarAutoPeekThreshold(_ minutes: Int) {
        let clamped = min(30, max(2, minutes))
        guard clamped != calendarAutoPeekThreshold else { return }
        calendarAutoPeekThreshold = clamped
        defaults?.set(clamped, forKey: "calendarAutoPeekThreshold")
        autoPeekScheduler?.threshold = clamped
        changed()
    }

    /// Settings › Version › Automatically check for updates switch.
    func setAutoCheckUpdates(_ on: Bool) {
        guard on != autoCheckUpdates else { return }
        autoCheckUpdates = on
        defaults?.set(on, forKey: "autoCheckUpdates")
        onAutoCheckUpdates?(on)
        changed()
    }

    private func applyCalendarAutoPeek() {
        if calendarAutoPeekEnabled && isEnabled(.calendar) {
            if autoPeekScheduler == nil {
                autoPeekScheduler = CalendarAutoPeekScheduler(calendar: calendar, threshold: calendarAutoPeekThreshold) { [weak self] state in
                    self?.setCalendarPeekState(state)
                }
            }
            autoPeekScheduler?.threshold = calendarAutoPeekThreshold
            autoPeekScheduler?.start()
        } else {
            autoPeekScheduler?.stop()
            autoPeekScheduler = nil
            setCalendarPeekState(nil)
        }
    }

    func setCalendarPeekState(_ state: CalendarPeekState?) {
        guard state != calendarPeekState else { return }
        calendarPeekState = state
        changed()
    }

    /// Opens the meeting URL in default browser and clears the peek state.
    func joinMeeting() {
        guard let url = calendarPeekState?.item.meetURL else { return }
        NSWorkspace.shared.open(url)
        autoPeekScheduler?.joined()
        setCalendarPeekState(nil)
    }

    /// Dismisses the auto-peek for the current meeting for the session.
    func dismissCalendarPeek() {
        autoPeekScheduler?.dismissCurrent()
        setCalendarPeekState(nil)
    }

    /// Collapses the auto-peek to a dot (or dismisses completely if already shrunk).
    func shrinkCalendarPeek() {
        guard let current = calendarPeekState else { return }
        if current.isShrunk && !current.isVisible {
            dismissCalendarPeek()
        } else {
            autoPeekScheduler?.shrinkCurrent(currentState: current)
        }
    }

    /// Expands the shrunk dot back to the full peek bar on hover/tap.
    func expandCalendarPeek() {
        guard let current = calendarPeekState, current.isShrunk else { return }
        autoPeekScheduler?.setReExpanded(true, currentState: current)
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
        if apply(.claude) {
            let on = isEnabled(.claude)
            if on, isEnabled(SubMenu.claudeAgents) { agents.start() } else { agents.stop() }
            if on, isEnabled(SubMenu.claudeTokens) { claudeUsage.startIfActive() } // no tab to show it in: no transcript scan
        }
        if apply(.calendar) {
            if isEnabled(.calendar) {
                applyCalendarAutoPeek()
            } else {
                calendar.stop()
                autoPeekScheduler?.stop()
                autoPeekScheduler = nil
                setCalendarPeekState(nil)
            }
        }
        if apply(.notes) {
            if isEnabled(.notes), isEnabled(SubMenu.notesTodo) { todoBridge.start() } else { todoBridge.stop() }
        }
    }

    /// Saved switches from before Claude was one menu: Agents and Sessions were menus of their own and Tokens & cost a claudex tab.
    /// They become Claude's tabs; with all three off the Claude menu is off. Anything already saved in the new form is kept.
    nonisolated static func migrated(features: [String], subs: [String]) -> (features: [String], subs: [String]) {
        let legacy: [(old: String, new: String)] = [("agents", "claudeAgents"), ("sessions", "claudeSessions")]
        var features = features, subs = subs
        for (old, new) in legacy where features.contains(old) {
            features.removeAll { $0 == old }
            if !subs.contains(new) { subs.append(new) }
        }
        if subs.contains("claudexTokens") {
            subs.removeAll { $0 == "claudexTokens" }
            if !subs.contains("claudeTokens") { subs.append("claudeTokens") }
        }
        let tabs = ["claudeTokens", "claudeAgents", "claudeSessions"]
        if tabs.allSatisfy(subs.contains) {
            subs.removeAll { tabs.contains($0) }
            if !features.contains("claude") { features.append("claude") }
        }
        return (features, subs)
    }

    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
    }

    func toggleSettings() {
        settings.toggle()
        changed()
    }

    /// Settings › Appearance: moves the shell to a corner or back to the top notch. Survives a relaunch.
    func setNotchPosition(_ p: NotchPosition) {
        guard p != notchPosition else { return }
        notchPosition = p
        defaults?.set(p.rawValue, forKey: "notchPosition")
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
