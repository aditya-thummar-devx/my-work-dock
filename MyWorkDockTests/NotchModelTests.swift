import XCTest
@testable import MyWorkDock

/// Manual clock for the model's 350 ms leave timer.
@MainActor
private final class FakeClock {
    private var jobs: [Int: (due: Double, work: @MainActor () -> Void)] = [:]
    private var next = 0
    private(set) var now = 0.0

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let id = next
        next += 1
        jobs[id] = (now + delay, work)
        return { [weak self] in self?.jobs[id] = nil }
    }

    func advance(_ dt: Double) {
        now += dt
        for (id, job) in jobs.sorted(by: { $0.key < $1.key }) where job.due <= now {
            jobs[id] = nil
            job.work()
        }
    }
}

@MainActor
final class NotchModelTests: XCTestCase {
    private var clock: FakeClock!
    private var model: NotchModel!

    override func setUp() async throws {
        clock = FakeClock()
        model = NotchModel(sample: true)
        let clock = clock!
        model.schedule = { clock.schedule($0, $1) }
    }

    func testHoverShowsPeekAndLeavingReturnsToIdleAfter350ms() {
        model.pointer(inside: true)
        XCTAssertEqual(model.mode, .peek)
        model.pointer(inside: false)
        clock.advance(0.34)
        XCTAssertEqual(model.mode, .peek)
        clock.advance(0.02)
        XCTAssertEqual(model.mode, .idle)
    }

    func testCopyFromAnyListClosesAndUnpinsThePanel() {
        model.clipboard.copyToClipboard = { _ in }
        for store in [model.commands, model.prompts, model.links] { store.copyToClipboard = { _ in } }
        let copies: [() -> Void] = [
            { self.model.clipboard.copy(self.model.clipboard.items[0].id) },
            { self.model.commands.copy(self.model.commands.items[0].id) },
            { self.model.prompts.copy(self.model.prompts.items[0].id) },
            { self.model.links.copy(self.model.links.items[0].id) },
        ]
        for copy in copies {
            model.openPanel()
            model.togglePin()
            copy()
            XCTAssertFalse(model.open)
            XCTAssertFalse(model.pinned)
        }
    }

    func testIsIdleOnlyWhilePanelClosedAndNothingPending() {
        XCTAssertTrue(model.isIdle)
        model.pointer(inside: true)
        XCTAssertFalse(model.isIdle)      // hovering
        model.openPanel()
        XCTAssertFalse(model.isIdle)      // open
        model.closePanel()
        XCTAssertTrue(model.isIdle)
        model.confirmer.ask(ConfirmRequest(title: "t", command: "c", note: "n", confirmTitle: "ok") {})
        XCTAssertFalse(model.isIdle)      // a confirm sheet is waiting
    }

    func testShrinkFlagFollowsModeSize() {
        XCTAssertFalse(model.shrinking)
        model.pointer(inside: true)
        XCTAssertFalse(model.shrinking)   // idle → peek grows
        model.openPanel()
        XCTAssertFalse(model.shrinking)   // peek → open grows
        model.closePanel()
        XCTAssertTrue(model.shrinking)    // open → idle shrinks
        model.pointer(inside: true)
        XCTAssertFalse(model.shrinking)   // idle → peek grows again
        model.pointer(inside: false)
        clock.advance(0.36)
        XCTAssertTrue(model.shrinking)    // peek → idle shrinks
    }

    func testReenteringCancelsTheLeaveTimer() {
        model.pointer(inside: true)
        model.openPanel()
        model.pointer(inside: false)
        clock.advance(0.2)
        model.pointer(inside: true)
        clock.advance(1)
        XCTAssertEqual(model.mode, .open)
    }

    func testLeavingClosesAnUnpinnedPanel() {
        model.pointer(inside: true)
        model.openPanel()
        model.pointer(inside: false)
        clock.advance(0.36)
        XCTAssertEqual(model.mode, .idle)
    }

    func testPinnedPanelNeverAutoCloses() {
        model.pointer(inside: true)
        model.openPanel()
        model.togglePin()
        model.pointer(inside: false)
        clock.advance(5)
        XCTAssertEqual(model.mode, .open)
        XCTAssertTrue(model.pinned)
    }

    func testCollapseClosesAndUnpins() {
        model.pointer(inside: true)
        model.openPanel()
        model.togglePin()
        model.closePanel()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertFalse(model.pinned)
    }

    func testKeyboardOpenedPanelStaysOpenUntilPointerHasEntered() {
        model.togglePanel()
        model.pointer(inside: false)
        clock.advance(5)
        XCTAssertEqual(model.mode, .open)
        model.pointer(inside: true)
        model.pointer(inside: false)
        clock.advance(0.36)
        XCTAssertEqual(model.mode, .idle)
    }

    func testTogglingWhilePinnedClosesAndUnpins() {
        model.openPanel()
        model.togglePin()
        model.togglePanel()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertFalse(model.pinned)
    }

    func testModePriorityIsOpenThenPeekThenLiveThenIdle() {
        XCTAssertEqual(model.mode, .idle)
        model.bootingOverride = "iPhone 16 Plus"
        XCTAssertEqual(model.mode, .live)
        model.pointer(inside: true)
        XCTAssertEqual(model.mode, .peek)
        model.openPanel()
        XCTAssertEqual(model.mode, .open)
    }

    func testIdleIsTheHardwareNotchWhenOneExists() {
        model.setBuddy(BuddyPrefs(on: false)) // the plain notch; with the buddy it grows by its ear (BuddyTests)
        XCTAssertEqual(model.geometry().width, Geo.idle.width)
        let g = model.geometry(notch: CGSize(width: 156, height: 28))
        XCTAssertEqual(g, Geo.hardwareNotchShell(CGSize(width: 156, height: 28)))
        // Height is the API's; width is the real cutout, narrower than the padded API width.
        XCTAssertEqual(g.height, 28)
        XCTAssertEqual(g.width, 156 * Geo.hardwareNotchPx.width / Geo.hardwareNotchPx.reportedWidth, accuracy: 1e-9)
        XCTAssertLessThan(g.width, 156)
        XCTAssertEqual(model.geometry(notch: nil).width, Geo.idle.width)
    }

    /// The hardware notch is fixed in panel pixels, so width and corners scale with the notch width across display modes.
    func testIdleCornersKeepTheirPhysicalSizeAcrossDisplayModes() {
        model.setBuddy(BuddyPrefs(on: false)) // the notch's own width, without the buddy's ear
        let narrow = model.geometry(notch: CGSize(width: 156, height: 28))
        let wide = model.geometry(notch: CGSize(width: 185, height: 32))
        XCTAssertEqual(narrow.radius / narrow.width, wide.radius / wide.width, accuracy: 1e-9)
        XCTAssertEqual(narrow.shoulder / narrow.width, wide.shoulder / wide.width, accuracy: 1e-9)
        // At the 14" default mode (370 px = 185 pt, 2 px/pt) the pixel constants are the point values * 2.
        XCTAssertEqual(wide.radius, Geo.hardwareNotchPx.radius / 2, accuracy: 1e-9)
        XCTAssertEqual(wide.width, Geo.hardwareNotchPx.width / 2, accuracy: 1e-9)
    }

    // MARK: Settings › Displays

    func testPeekAndOpenBelongToTheActiveDisplayOnly() {
        model.setActiveDisplay(1)
        model.pointer(inside: true)
        XCTAssertEqual(model.mode(on: 1), .peek)
        XCTAssertEqual(model.mode(on: 2), .idle)
        model.openPanel()
        XCTAssertEqual(model.mode(on: 1), .open)
        XCTAssertEqual(model.mode(on: 2), .idle)
        XCTAssertEqual(model.geometry(on: 2).width, Geo.idle.width + Geo.Buddy.ear) // the buddy is on by default
        XCTAssertEqual(model.geometry(on: 1).width, Geo.open.width)
    }

    func testLargePanelTakesThreeQuartersOfTheDisplayAndNeverShrinksBelowMedium() {
        let screen = CGSize(width: 1600, height: 1000)
        model.openPanel()
        XCTAssertEqual(model.geometry(screen: screen).width, Geo.open.width) // medium is the default
        model.setPanelSize(.large)
        XCTAssertEqual(model.geometry(screen: screen).width, 1200)
        XCTAssertEqual(model.geometry(screen: screen).height, 750)
        XCTAssertEqual(model.geometry(screen: CGSize(width: 800, height: 600)).height, Geo.open.height)
        XCTAssertEqual(model.geometry().width, Geo.open.width) // unknown display
    }

    func testLiveActivityShowsOnEveryDisplayEvenWhileAnotherPeeks() {
        model.setActiveDisplay(1)
        model.bootingOverride = "iPhone 16 Plus"
        XCTAssertEqual([model.mode(on: 1), model.mode(on: 2)], [.live, .live])
        model.pointer(inside: true)
        XCTAssertEqual([model.mode(on: 1), model.mode(on: 2)], [.peek, .live])
    }

    func testWithoutAnActiveDisplayEveryShellFollowsTheMode() {
        model.pointer(inside: true)
        XCTAssertEqual([model.mode(on: nil), model.mode(on: 7)], [.peek, .peek])
    }

    func testShowOnAllDisplaysDefaultsOffAndToggles() {
        XCTAssertFalse(model.showOnAllDisplays)
        model.setShowOnAllDisplays(true)
        XCTAssertTrue(model.showOnAllDisplays)
    }

    func testAutoCheckUpdatesDefaultsOnAndTogglesAndNotifies() {
        XCTAssertTrue(model.autoCheckUpdates)
        var notified: Bool?
        model.onAutoCheckUpdates = { notified = $0 }
        model.setAutoCheckUpdates(false)
        XCTAssertFalse(model.autoCheckUpdates)
        XCTAssertEqual(notified, false)
        model.setAutoCheckUpdates(true)
        XCTAssertTrue(model.autoCheckUpdates)
        XCTAssertEqual(notified, true)
    }

    func testPeekHugsItsEarsAroundTheCentredKeepOut() {
        model.setPeekEnabled(.claudex, true)
        model.pointer(inside: true)
        let g = model.geometry(), e = model.peekExtents
        XCTAssertEqual(g.width, Geo.keepOutWidth + e.left + e.right)
        XCTAssertEqual(g.centerOffset, (e.right - e.left) / 2)
        // The shell's left edge sits `left + 100` pt from the hardware-notch centre.
        XCTAssertEqual(g.centerOffset - g.width / 2, -(e.left + Geo.keepOutWidth / 2))
    }

    // MARK: Settings › Menus

    func testFeatureRawValuesAreStable() {
        // Stored in UserDefaults as "disabledFeatures".
        XCTAssertEqual(Feature.allCases.map(\.rawValue), ["clipboard", "calendar", "notes", "claude", "claudex", "emulator", "localIP"])
    }

    func testClaudeSitsBeforeClaudexAndCanBeSwitchedOff() {
        XCTAssertEqual(model.enabledTabs, [.clipboard, .calendar, .notes, .claude, .claudex, .emulator])
        XCTAssertEqual(MainTab.claude.label, "Claude")
        XCTAssertEqual(model.enabledClaudeTabs, [.agents, .sessions, .tokens])
        model.setEnabled(.claude, false)
        XCTAssertEqual(model.enabledTabs, [.clipboard, .calendar, .notes, .claudex, .emulator])
    }

    func testShowOnBoardOpensClaudeSessionsFocusedOnTheSession() {
        model.showOnBoard("abc")
        XCTAssertEqual(model.mainTab, .claude)
        XCTAssertEqual(model.claudeTab, .sessions)
        XCTAssertEqual(model.sessions.focusID, "abc")
        model.setMainTab(.notes)
        model.setEnabled(SubMenu.claudeSessions, false)
        model.showOnBoard("def") // no Sessions tab to show it on
        XCTAssertEqual(model.mainTab, .notes)
    }

    func testClaudeKeepsItsTabAndAnApprovalAsksForAgents() {
        model.setClaudeTab(.sessions)
        model.setMainTab(.notes)
        model.setMainTab(.claude)
        XCTAssertEqual(model.claudeTab, .sessions) // where you left it
        model.cycleInnerTab()
        XCTAssertEqual(model.claudeTab, .tokens)
        model.cycleInnerTab()
        XCTAssertEqual(model.claudeTab, .agents) // wraps: Tokens & cost is last
        model.setEnabled(SubMenu.claudeAgents, false)
        XCTAssertEqual(model.claudeTab, .sessions) // the tab on screen moved to the first one showing
        model.setEnabled(SubMenu.claudeAgents, true)
    }

    func testSavedSwitchesFromBeforeClaudeMoveIntoIt() {
        func migrated(_ f: [String], _ s: [String] = []) -> (features: [String], subs: [String]) { NotchModel.migrated(features: f, subs: s) }
        XCTAssertEqual(migrated(["emulator"]).features, ["emulator"])
        XCTAssertEqual(migrated(["agents", "emulator"]).features, ["emulator"])
        XCTAssertEqual(migrated(["agents", "emulator"]).subs, ["claudeAgents"])
        XCTAssertEqual(migrated(["sessions"], ["notesTodo", "claudexTokens"]).subs, ["notesTodo", "claudeSessions", "claudeTokens"])
        // Everything of Claude's was off: the menu is off, and its tabs are not left all off under a menu that is back on.
        let all = migrated(["agents", "sessions"], ["claudexTokens"])
        XCTAssertEqual(all.features, ["claude"])
        XCTAssertEqual(all.subs, [])
        XCTAssertEqual(migrated(all.features, all.subs).features, ["claude"]) // nothing left to migrate
        XCTAssertEqual(migrated(["claude"], ["claudeAgents"]).subs, ["claudeAgents"])
    }

    func testDisablingTheCurrentMenuMovesToTheNextEnabledOne() {
        model.setMainTab(.notes)
        model.setEnabled(.clipboard, false)
        model.setEnabled(.notes, false)
        XCTAssertEqual(model.mainTab, .calendar) // the first enabled one takes over
        model.setEnabled(.calendar, false)
        model.setEnabled(.claude, false)
        XCTAssertEqual(model.enabledTabs, [.claudex, .emulator])
        XCTAssertEqual(model.mainTab, .claudex)
        model.setEnabled(.claudex, false)
        XCTAssertEqual(model.mainTab, .emulator)
        model.setEnabled(.emulator, false)
        XCTAssertTrue(model.enabledTabs.isEmpty)
        model.setEnabled(.notes, true)
        XCTAssertEqual(model.enabledTabs, [.notes])
        XCTAssertEqual(model.mainTab, .notes)
    }

    // MARK: Settings screen

    func testPickingAMenuLeavesTheSettingsScreen() {
        model.openPanel()
        model.toggleSettings()
        XCTAssertTrue(model.settings)
        model.setMainTab(.notes)
        XCTAssertFalse(model.settings)
    }

    func testHotkeyOnTheCurrentMenuLeavesTheSettingsScreen() {
        model.setMainTab(.notes)
        model.openPanel()
        model.toggleSettings()
        model.show(.notes) // same menu: setMainTab is not called, the screen still has to go
        XCTAssertFalse(model.settings)
        XCTAssertEqual(model.mainTab, .notes)
    }

    func testSwitchingOffTheCurrentMenuFromSettingsStaysInSettings() {
        model.setMainTab(.notes)
        model.openPanel()
        model.toggleSettings()
        model.setEnabled(.notes, false) // another menu takes over behind the screen
        XCTAssertTrue(model.settings)
        XCTAssertNotEqual(model.mainTab, .notes)
    }

    func testInnerTabKeyDoesNothingOnTheSettingsScreen() {
        model.setMainTab(.notes)
        let before = model.notesTab
        model.openPanel()
        model.toggleSettings()
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, before)
    }

    func testCalendarSitsBetweenClipboardAndNotes() {
        XCTAssertEqual(MainTab.allCases, [.clipboard, .calendar, .notes, .claude, .claudex, .emulator])
        XCTAssertEqual(MainTab.calendar.label, "My Calendar")
        model.setMainTab(.clipboard)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .calendar)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .notes)
    }

    func testLeavingTheCalendarTabOrThePanelClosesItsEventSheet() {
        model.calendar.preview(.signedIn(email: "me@devxlabs.ai"), selecting: "Dentist")
        XCTAssertNotNil(model.calendar.selected)
        model.setMainTab(.notes)
        XCTAssertNil(model.calendar.selected)
        model.calendar.preview(.signedIn(email: "me@devxlabs.ai"), selecting: "Dentist")
        model.closePanel()
        XCTAssertNil(model.calendar.selected)
    }

    func testSigningInKeepsTheUpdaterWaitingAndLeavingTheMenuCancelsIt() {
        XCTAssertTrue(model.isIdle)
        model.calendar.preview(.signingIn)
        XCTAssertFalse(model.isIdle) // Sparkle must not relaunch the app while the browser flow runs
        model.setEnabled(.calendar, false)
        XCTAssertEqual(model.calendar.auth, .signedOut(nil))
        XCTAssertTrue(model.isIdle)
    }

    func testCycleMainTabWrapsAndSkipsDisabledMenus() {
        model.setEnabled(.calendar, false)
        model.setMainTab(.clipboard)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .notes)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .claude)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .claudex)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .emulator)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .clipboard)
        model.setEnabled(.claudex, false)
        model.setEnabled(.claude, false)
        model.setMainTab(.notes)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .emulator)
        model.setEnabled(.emulator, false)
        XCTAssertEqual(model.mainTab, .clipboard) // the disabled current menu hands over to the first enabled one
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .notes)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .clipboard)
        model.setEnabled(.clipboard, false)
        XCTAssertEqual(model.mainTab, .notes)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .notes) // one menu left: nothing to cycle to
    }

    func testShowOpensPanelOnRequestedMenuAndSkipsDisabledOnes() {
        model.setMainTab(.claudex)
        model.show(.notes, notes: .prompts)
        XCTAssertTrue(model.open)
        XCTAssertEqual(model.mainTab, .notes)
        XCTAssertEqual(model.notesTab, .prompts)
        model.show(.notes, notes: .links)
        XCTAssertEqual(model.notesTab, .links)
        model.show(.emulator)
        XCTAssertEqual(model.mainTab, .emulator)
        model.setEnabled(.claudex, false)
        model.show(.claudex)
        XCTAssertEqual(model.mainTab, .emulator) // switched-off menu: nothing happens
    }

    func testCycleInnerTabWrapsWithinTheVisibleMainMenu() {
        model.setMainTab(.notes)
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, .commands)
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, .prompts)
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, .links)
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, .todo)
        model.setMainTab(.claudex)
        for tab in [ClaudexTab.pool, .play, .health, .usage] {
            model.cycleInnerTab()
            XCTAssertEqual(model.claudex.tab, tab)
        }
        model.setMainTab(.emulator)
        model.emulator.targetMenuOpen = true
        model.cycleInnerTab()
        XCTAssertEqual(model.emulatorTab, .wireless)
        XCTAssertFalse(model.emulator.targetMenuOpen)
        model.cycleInnerTab()
        model.cycleInnerTab()
        XCTAssertEqual(model.emulatorTab, .devices)
        XCTAssertEqual(model.mainTab, .emulator) // inner cycling never leaves the main menu
    }

    func testTokensAndCostDoesNotNeedClaudex() {
        model.claudex.showSampleUnavailable()
        model.setMainTab(.claude)
        model.setClaudeTab(.tokens)
        XCTAssertNotNil(model.claudeUsage.snapshot)
        XCTAssertEqual(model.claudex.visibleTabs, []) // claudex shows only why it is missing
        model.setEnabled(.claudex, false)
        XCTAssertEqual(model.enabledClaudeTabs, [.agents, .sessions, .tokens]) // and switching it off leaves Claude alone
        model.show(.claude)
        XCTAssertTrue(model.open)
        XCTAssertEqual(model.mainTab, .claude)
    }

    func testCollapsingClosesTheDetailsSheet() throws {
        let name = try XCTUnwrap(model.claudex.members.data?.first?.name)
        model.pointer(inside: true)
        model.openPanel()
        model.claudex.openDetail(name)
        XCTAssertEqual(model.claudex.detailName, name)
        model.pointer(inside: false)
        clock.advance(0.36)
        XCTAssertNil(model.claudex.detailName)
        model.claudex.openDetail(name)
        model.closePanel()
        XCTAssertNil(model.claudex.detailName)
        model.claudex.openDetail(name)
        model.setMainTab(.notes)
        XCTAssertNil(model.claudex.detailName)
    }


    func testClipboardIsTheFirstMenuAndHasItsOwnHotkeyAndSearch() {
        XCTAssertEqual(model.mainTab, .clipboard)
        XCTAssertEqual(model.enabledTabs.first, .clipboard)
        model.openSearch() // ⌘F
        XCTAssertTrue(model.clipboard.searchOpen)
        model.setMainTab(.claudex)
        model.show(.clipboard) // ⌘⇧V
        XCTAssertTrue(model.open)
        XCTAssertEqual(model.mainTab, .clipboard)
    }

    func testLoweringTheClipboardLimitAsksFirstAndRaisingItDoesNot() async {
        var n = 0
        model.clipboard.changeCount = { n }
        model.clipboard.readText = { "clip \(n)" }
        for i in 1...5 { n = i; model.clipboard.poll() } // five untagged clips (the sample ones are tagged)
        model.setClipboardLimit(2)
        XCTAssertNotNil(model.confirmer.pending) // would delete 3
        XCTAssertEqual(model.confirmer.pending?.confirmTitle, "Delete 3")
        XCTAssertEqual(model.clipboard.limit, ClipboardStore.defaultLimit)
        model.confirmer.cancel()
        XCTAssertEqual(model.clipboard.items.count, 4 + 5)
        model.setClipboardLimit(2)
        await model.confirmer.pending?.run() // what the sheet's Delete button does
        model.confirmer.cancel() // (tests clear the sheet by hand)
        XCTAssertEqual(model.clipboard.limit, 2)
        XCTAssertEqual(model.clipboard.items.count, 4 + 2) // the four tagged samples stay
        model.setClipboardLimit(500) // raising deletes nothing: applied at once
        XCTAssertNil(model.confirmer.pending)
        XCTAssertEqual(model.clipboard.limit, 500)
    }

    func testClipboardSharesConfirmerWithNotchModel() async {
        XCTAssertTrue(model.clipboard.confirmer === model.confirmer)
        XCTAssertFalse(model.clipboard.items.isEmpty)
        model.clipboard.requestClearAll()
        XCTAssertNotNil(model.confirmer.pending)
        model.confirmer.cancel()
    }

    func testDisabledNotesIgnoresSearchAndUndoEvenWhileItIsTheLastTab() {

        model.setMainTab(.notes)
        model.setNotesTab(.commands)
        XCTAssertNotNil(model.activeSnippets)
        model.setEnabled(.clipboard, false)
        model.setEnabled(.calendar, false)
        model.setEnabled(.claude, false)
        model.setEnabled(.claudex, false)
        model.setEnabled(.emulator, false)
        model.setEnabled(.notes, false) // mainTab stays .notes: nothing else to move to
        XCTAssertEqual(model.mainTab, .notes)
        XCTAssertNil(model.activeSnippets)
        XCTAssertNil(model.pendingUndo)
    }

    func testEmulatorOffHidesTheLiveActivity() {
        model.emulator.showBootingSample()
        XCTAssertEqual(model.mode, .live)
        model.setEnabled(.emulator, false)
        XCTAssertNil(model.bootingName)
        XCTAssertEqual(model.mode, .idle)
        model.bootingOverride = "iPhone 16 Plus"
        XCTAssertEqual(model.mode, .idle)
        model.setEnabled(.emulator, true)
        XCTAssertEqual(model.mode, .live)
    }

    // MARK: Settings › Menus › sub-tabs

    func testSubMenuRawValuesAreStableAndEveryTabHasOne() {
        // Stored in UserDefaults as "disabledSubMenus".
        XCTAssertEqual(SubMenu.allCases.map(\.rawValue), ["notesTodo", "notesCommands", "notesPrompts", "notesLinks",
                                                          "emulatorDevices", "emulatorWireless", "emulatorTunnel",
                                                          "claudeAgents", "claudeSessions", "claudeTokens",
                                                          "claudexUsage", "claudexPool", "claudexPlay", "claudexHealth"])
        XCTAssertEqual(NotesTab.allCases.map { SubMenu($0).parent }, Array(repeating: .notes, count: NotesTab.allCases.count))
        XCTAssertEqual(EmulatorTab.allCases.map { SubMenu($0).parent }, Array(repeating: .emulator, count: EmulatorTab.allCases.count))
        XCTAssertEqual(ClaudeTab.allCases.map { SubMenu($0).parent }, Array(repeating: .claude, count: ClaudeTab.allCases.count))
        XCTAssertEqual(ClaudexTab.allCases.map { SubMenu($0).parent }, Array(repeating: .claudex, count: ClaudexTab.allCases.count))
        XCTAssertEqual(SubMenu.allCases.count, NotesTab.allCases.count + EmulatorTab.allCases.count + ClaudeTab.allCases.count + ClaudexTab.allCases.count)
    }

    func testEverySubTabIsOnByDefault() {
        XCTAssertTrue(model.disabledSubs.isEmpty)
        XCTAssertEqual(model.enabledNotesTabs, NotesTab.allCases)
        XCTAssertEqual(model.enabledEmulatorTabs, EmulatorTab.allCases)
        XCTAssertEqual(model.claudex.visibleTabs, ClaudexTab.allCases)
    }

    func testSwitchingOffTheTabOnScreenMovesToTheFirstOneLeft() {
        model.setMainTab(.notes)
        model.setEnabled(SubMenu.notesTodo, false)
        XCTAssertEqual(model.notesTab, .commands)
        XCTAssertEqual(model.enabledNotesTabs, [.commands, .prompts, .links])
        model.setEnabled(SubMenu.notesLinks, false) // not the one on screen: it stays
        XCTAssertEqual(model.notesTab, .commands)
        model.setEnabled(SubMenu.emulatorDevices, false)
        XCTAssertEqual(model.emulatorTab, .wireless)
        model.claudex.select(.pool)
        model.setEnabled(SubMenu.claudexPool, false)
        XCTAssertEqual(model.claudex.activeTab, .usage)
        XCTAssertFalse(model.claudex.visibleTabs.contains(.pool))
    }

    func testTheLastSubTabCannotBeSwitchedOff() {
        for sub in [SubMenu.notesCommands, .notesPrompts, .notesLinks] { model.setEnabled(sub, false) }
        model.setEnabled(SubMenu.notesTodo, false)
        XCTAssertTrue(model.isEnabled(SubMenu.notesTodo))
        XCTAssertEqual(model.enabledNotesTabs, [.todo])
        model.setEnabled(SubMenu.notesLinks, true) // another one back on frees it
        model.setEnabled(SubMenu.notesTodo, false)
        XCTAssertEqual(model.enabledNotesTabs, [.links])
    }

    func testShiftTabSkipsSwitchedOffSubTabs() {
        model.setEnabled(SubMenu.notesCommands, false)
        model.setEnabled(SubMenu.notesLinks, false)
        model.setMainTab(.notes)
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, .prompts)
        model.cycleInnerTab()
        XCTAssertEqual(model.notesTab, .todo)
        model.setEnabled(SubMenu.notesPrompts, false)
        model.cycleInnerTab() // TODO is all that is left: nothing to cycle to, and no reset of its draft
        XCTAssertEqual(model.notesTab, .todo)

        model.setEnabled(SubMenu.claudexPlay, false)
        model.setMainTab(.claudex)
        model.claudex.select(.pool)
        model.cycleInnerTab()
        XCTAssertEqual(model.claudex.activeTab, .health)
        model.setEnabled(SubMenu.emulatorWireless, false)
        model.setMainTab(.emulator)
        model.cycleInnerTab()
        XCTAssertEqual(model.emulatorTab, .tunnel)
    }

    func testAHotkeyForASwitchedOffNotesTabLeavesNotesWhereItWas() {
        model.setEnabled(SubMenu.notesTodo, false) // Notes is on Commands now
        model.show(.notes, notes: .todo)
        XCTAssertEqual(model.mainTab, .notes)
        XCTAssertEqual(model.notesTab, .commands)
        XCTAssertTrue(model.open)
        model.show(.notes, notes: .links)
        XCTAssertEqual(model.notesTab, .links)
    }

    func testSubTabChoicesStayWhileTheirMenuIsOff() {
        model.setEnabled(SubMenu.notesLinks, false)
        model.setEnabled(.notes, false)
        XCTAssertEqual(model.disabledSubs, [.notesLinks])
        model.setEnabled(.notes, true)
        XCTAssertEqual(model.enabledNotesTabs, [.todo, .commands, .prompts])
    }

    func testTheTodoCountNeedsNotesTodo() {
        model.pointer(inside: true)
        model.setEnabled(SubMenu.notesTodo, false)
        assertInfo(clips: Self.clips, ip: Self.ip)
        model.setEnabled(SubMenu.notesTodo, true)
        assertInfo(todo: Self.todo, clips: Self.clips, ip: Self.ip)
    }

    func testMenuColumnsBreakWhereTheyComeOutMostEven() {
        XCTAssertEqual(MenuColumns.split([1, 1, 1, 1, 1, 1, 1, 1]), 4) // no sub-tabs: four and four
        XCTAssertEqual(MenuColumns.split([1, 1, 5, 6, 4, 1, 1, 1]), 3) // a tie takes the earlier break
        XCTAssertEqual(MenuColumns.split([9, 1, 1]), 1) // the first menu always stays left
        XCTAssertEqual(MenuColumns.split([1]), 1)
    }

    // MARK: Settings › Peek

    func testPeekSourceRawValuesAreStable() {
        // Stored in UserDefaults as "peekSources".
        XCTAssertEqual(PeekSource.allCases.map(\.rawValue), ["claudex", "todo", "clipboard", "localIP", "events"])
    }

    private static let todo = PeekTodo(left: 3, done: 2)
    private static let clips = PeekClips(total: 4, pinned: 1)
    private static let ip = "192.168.1.24"

    /// The shell hugs the ears the content measures: counts left of the notch, the IP right of it, an empty side 0 wide.
    private func assertInfo(todo: PeekTodo? = nil, clips: PeekClips? = nil, ip: String? = nil,
                            file: StaticString = #filePath, line: UInt = #line) {
        let info = PeekInfo(todo: todo, clips: clips, ip: ip)
        XCTAssertEqual(model.peekContent, .info(info), file: file, line: line)
        let e = PeekMetrics.measure(info)
        XCTAssertEqual(e.left > 0, info.hasLeft, file: file, line: line)
        XCTAssertEqual(e.right > 0, ip != nil, file: file, line: line)
        XCTAssertEqual(model.geometry().width, Geo.keepOutWidth + e.left + e.right, file: file, line: line)
        XCTAssertEqual(model.geometry().centerOffset, (e.right - e.left) / 2, file: file, line: line)
    }

    func testPeekDefaultsToClaudexOffWithTodoClipsAndIPOn() {
        XCTAssertEqual(model.peekOn, [.todo, .clipboard, .localIP])
        model.pointer(inside: true)
        XCTAssertEqual(model.mode, .peek)
        assertInfo(todo: Self.todo, clips: Self.clips, ip: Self.ip)
    }

    func testClaudexOnTakesTheWholePeekAndSwitchesTheOthersOff() {
        model.setPeekEnabled(.claudex, true)
        XCTAssertEqual(model.peekOn, [.claudex])
        model.pointer(inside: true)
        XCTAssertEqual(model.peekContent, .claudex)
        XCTAssertEqual(model.geometry().width, Geo.keepOutWidth + model.peekExtents.left + model.peekExtents.right)
        model.setPeekEnabled(.todo, true) // locked while claudex is on
        XCTAssertEqual(model.peekOn, [.claudex])
    }

    func testClaudexOffPutsEveryOtherSourceBackOn() {
        model.setPeekEnabled(.todo, false)
        model.setPeekEnabled(.localIP, false)
        model.setPeekEnabled(.claudex, true)
        model.setPeekEnabled(.claudex, false)
        XCTAssertEqual(model.peekOn, [.todo, .clipboard, .localIP])
    }

    func testAPartWithNothingToShowIsHiddenAndTheOthersKeepTheirSide() {
        model.pointer(inside: true)
        model.setPeekEnabled(.todo, false)
        assertInfo(clips: Self.clips, ip: Self.ip) // clips stay on the left
        model.setPeekEnabled(.localIP, false)
        assertInfo(clips: Self.clips) // left only: the shell grows left
        XCTAssertLessThan(model.geometry().centerOffset, 0)
        model.setPeekEnabled(.localIP, true)
        model.setPeekEnabled(.clipboard, false)
        assertInfo(ip: Self.ip) // IP only: the shell grows right
        XCTAssertGreaterThan(model.geometry().centerOffset, 0)
    }

    func testAMenuThatIsOffHidesItsPart() {
        model.pointer(inside: true)
        model.setEnabled(.notes, false)
        assertInfo(clips: Self.clips, ip: Self.ip)
        model.setEnabled(.clipboard, false)
        assertInfo(ip: Self.ip)
    }

    func testNoNetworkHidesTheIPButTheCountsStayOnTheLeft() {
        model.localIP.read = { nil }
        model.localIP.refresh()
        model.pointer(inside: true)
        assertInfo(todo: Self.todo, clips: Self.clips)
        XCTAssertEqual(PeekMetrics.measure(PeekInfo(todo: Self.todo, clips: Self.clips)).right, 0)
    }

    func testPeekShowsTheHintWhenNothingIsLeftToShow() {
        for source in [PeekSource.todo, .clipboard, .localIP] { model.setPeekEnabled(source, false) }
        model.pointer(inside: true)
        XCTAssertEqual(model.peekContent, .hint)
        XCTAssertEqual(model.geometry().width, Geo.keepOutWidth + PeekMetrics.hintExtents.right)
        XCTAssertEqual(model.geometry().centerOffset, PeekMetrics.hintExtents.right / 2)
    }

    func testClaudexOnWithItsMenuOffShowsTheHint() {
        model.setPeekEnabled(.claudex, true)
        model.setEnabled(.claudex, false)
        XCTAssertEqual(model.peekContent, .hint)
    }

    func testSettingAPeekSwitchTwiceChangesNothing() {
        var calls = 0
        model.onChange = { calls += 1 }
        model.setPeekEnabled(.todo, true) // already on
        XCTAssertEqual(calls, 0)
        model.setPeekEnabled(.todo, false)
        model.setPeekEnabled(.todo, false)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.peekOn, [.clipboard, .localIP])
    }

    func testTurningAMenuBackOnRestoresItsPeekAndTab() {
        model.setEnabled(.claudex, false)
        model.setEnabled(.claudex, true)
        XCTAssertEqual(model.enabledTabs, MainTab.allCases)
    }

    // MARK: Today's events in the peek

    /// Signed in on the sample Wednesday (10:30), the row switched on.
    private func enableEvents(at now: Date? = nil) {
        model.calendar.preview(.signedIn(email: "me@devxlabs.ai"))
        if let now { model.calendar.now = { now } }
        model.setPeekEnabled(.events, true)
    }

    func testTodaysEventsAreOffByDefaultAndClaudexNeitherTakesThemOffNorLocksThem() {
        XCTAssertFalse(model.isPeekEnabled(.events))
        model.setPeekEnabled(.events, true)
        XCTAssertEqual(model.peekOn, [.todo, .clipboard, .localIP, .events])
        model.setPeekEnabled(.claudex, true) // takes the ears, leaves the row
        XCTAssertEqual(model.peekOn, [.claudex, .events])
        model.setPeekEnabled(.events, false) // the row still changes while claudex is on
        XCTAssertEqual(model.peekOn, [.claudex])
        model.setPeekEnabled(.events, true)
        model.setPeekEnabled(.claudex, false) // puts the ears back, keeps the row
        XCTAssertEqual(model.peekOn, [.todo, .clipboard, .localIP, .events])
    }

    func testSavedPeekChoicesKeepTheRowAndClaudexStaysAloneAmongTheEars() {
        XCTAssertEqual(PeekSource.restored(["claudex", "todo", "events"]), [.claudex, .events])
        XCTAssertEqual(PeekSource.restored(["todo", "clipboard"]), [.todo, .clipboard])
        XCTAssertEqual(PeekSource.restored(["events"]), [.events])
        XCTAssertEqual(PeekSource.restored(["bogus"]), [])
    }

    func testThePeekGrowsByTheEventsRowAndTheEarsStayAgainstTheNotch() throws {
        enableEvents()
        model.pointer(inside: true)
        let events = try XCTUnwrap(model.peekEvents)
        XCTAssertEqual(events.rows.map(\.title), ["Client call: Asaya rollout", "Quarterly review prep", "Hotfix triage"]) // Standup is over, Gym is the "+1"
        XCTAssertEqual(events.more, 1)
        let ears = PeekMetrics.measure(PeekInfo(todo: Self.todo, clips: Self.clips, ip: Self.ip))
        let g = model.geometry()
        XCTAssertEqual(g.height, Geo.peek.height + events.height)
        XCTAssertEqual(g.width, max(Geo.keepOutWidth + ears.left + ears.right, Geo.Peek.eventsMinWidth))
        XCTAssertEqual(g.centerOffset, (ears.right - ears.left) / 2) // the notch keeps its place
    }

    func testTheRowSitsUnderClaudexToo() throws {
        model.setPeekEnabled(.claudex, true)
        enableEvents()
        model.pointer(inside: true)
        XCTAssertEqual(model.peekContent, .claudex)
        let events = try XCTUnwrap(model.peekEvents)
        XCTAssertEqual(model.geometry().height, Geo.peek.height + events.height)
        XCTAssertEqual(model.geometry().width, max(Geo.keepOutWidth + model.peekExtents.left + model.peekExtents.right, Geo.Peek.eventsMinWidth))
    }

    func testTheRowNeedsSignInLoadedEventsAndTheMenu() {
        model.setPeekEnabled(.events, true)
        model.pointer(inside: true)
        XCTAssertNil(model.peekEvents) // the sample store starts signed out
        XCTAssertEqual(model.geometry().height, Geo.peek.height)
        model.calendar.preview(.signedIn(email: "me@devxlabs.ai"))
        model.refreshPeekEvents()
        XCTAssertNotNil(model.peekEvents)
        model.setEnabled(.calendar, false) // My Calendar off: its data is dropped and the row goes
        model.refreshPeekEvents()
        XCTAssertNil(model.peekEvents)
    }

    func testSwitchingTheRowOffRemovesItAtOnce() {
        enableEvents()
        XCTAssertNotNil(model.peekEvents)
        model.setPeekEnabled(.events, false)
        XCTAssertNil(model.peekEvents)
    }

    func testNothingLeftTodayShowsOneLine() throws {
        enableEvents(at: CalendarSample.date(21, 20, 0))
        model.pointer(inside: true)
        let events = try XCTUnwrap(model.peekEvents)
        XCTAssertTrue(events.rows.isEmpty)
        XCTAssertEqual(events.more, 0)
        XCTAssertEqual(events.height, Geo.Peek.eventsDivider + Geo.Peek.eventsTop + Geo.Peek.eventRow + Geo.Peek.eventsBottom)
        XCTAssertEqual(events.spoken, "No more events today")
    }

    func testClickingTheEventsOpensMyCalendarOnToday() {
        model.calendar.preview(.signedIn(email: "me@devxlabs.ai"))
        model.calendar.go(.next) // the tab was left on next week
        XCTAssertFalse(model.calendar.cal.isDate(model.calendar.anchor, inSameDayAs: model.calendar.now()))
        model.pointer(inside: true)
        model.showToday()
        XCTAssertTrue(model.open)
        XCTAssertEqual(model.mainTab, .calendar)
        XCTAssertTrue(model.calendar.cal.isDate(model.calendar.anchor, inSameDayAs: model.calendar.now()))
        XCTAssertEqual(model.calendar.mode, .week) // the view the user chose stays
    }

    func testClickingAnEventInThePeekOpensItInMyCalendarScrolledToIt() throws {
        enableEvents()
        model.mainTab = .notes // the panel was left on another tab
        model.pointer(inside: true)
        let hotfix = try XCTUnwrap(model.peekEvents?.rows.last).event // 10:45
        model.showEvent(hotfix)
        XCTAssertTrue(model.open)
        XCTAssertEqual(model.mainTab, .calendar)
        XCTAssertEqual(model.calendar.selected?.id, hotfix.id) // its sheet is open: switching to the tab did not close it
        XCTAssertEqual(model.calendar.focus, hotfix.start) // and the grid scrolls to it
        XCTAssertTrue(model.calendar.cal.isDate(model.calendar.anchor, inSameDayAs: model.calendar.now()))
    }

    func testTheRowIsSpokenAsTheNextEvents() throws {
        enableEvents()
        let events = try XCTUnwrap(model.peekEvents)
        XCTAssertEqual(events.spoken, "Today: Client call: Asaya rollout, now. Quarterly review prep, now. Hotfix triage, in 15 min. 1 more")
    }

    func testEventTimingReadsNowThenMinutesThenHours() {
        let now = CalendarSample.date(21, 10, 30)
        func timing(_ seconds: TimeInterval) -> String { PeekEvents.timing(from: now.addingTimeInterval(seconds), now: now) }
        XCTAssertEqual(timing(0), "now")
        XCTAssertEqual(timing(-600), "now") // running
        XCTAssertEqual(timing(30), "in 1 min") // rounds up
        XCTAssertEqual(timing(15 * 60), "in 15 min")
        XCTAssertEqual(timing(59 * 60), "in 59 min")
        XCTAssertEqual(timing(60 * 60), "in 1 h")
        XCTAssertEqual(timing(65 * 60), "in 1 h 5 min")
        XCTAssertEqual(timing(8 * 3600 + 120), "in 8 h 2 min")
    }
}
