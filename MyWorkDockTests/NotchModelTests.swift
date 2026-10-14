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
        XCTAssertEqual(model.geometry().width, Geo.idle.width)
        let g = model.geometry(notch: CGSize(width: 156, height: 28))
        XCTAssertEqual([g.width, g.height, g.radius, g.shoulder],
                       [156, 28, Geo.hardwareNotch.radius, Geo.hardwareNotch.shoulder])
        XCTAssertEqual(model.geometry(notch: nil).width, Geo.idle.width)
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
        XCTAssertEqual(model.geometry(on: 2).width, Geo.idle.width)
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

    func testPeekHugsItsEarsAroundTheCentredKeepOut() {
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
        XCTAssertEqual(Feature.allCases.map(\.rawValue), ["clipboard", "notes", "claudex", "emulator", "localIP"])
    }

    func testDisablingTheCurrentMenuMovesToTheNextEnabledOne() {
        model.setMainTab(.notes)
        model.setEnabled(.clipboard, false)
        model.setEnabled(.notes, false)
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

    func testCycleMainTabWrapsAndSkipsDisabledMenus() {
        model.setMainTab(.clipboard)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .notes)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .claudex)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .emulator)
        model.cycleMainTab()
        XCTAssertEqual(model.mainTab, .clipboard)
        model.setEnabled(.claudex, false)
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

    func testDisabledNotesIgnoresSearchAndUndoEvenWhileItIsTheLastTab() {

        model.setMainTab(.notes)
        model.setNotesTab(.commands)
        XCTAssertNotNil(model.activeSnippets)
        model.setEnabled(.clipboard, false)
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

    func testClaudexOffPeeksWithTheHintOnTheRightOfTheNotch() {
        XCTAssertFalse(model.peekHint)
        model.setEnabled(.claudex, false)
        model.pointer(inside: true)
        XCTAssertEqual(model.mode, .peek)
        XCTAssertTrue(model.peekHint)
        let hint = PeekMetrics.hintExtents
        XCTAssertGreaterThan(hint.right, 0)
        XCTAssertEqual(hint.left, 0)
        XCTAssertEqual(model.geometry().width, Geo.keepOutWidth + hint.right)
        XCTAssertEqual(model.geometry().centerOffset, hint.right / 2)
    }

    func testTurningAMenuBackOnRestoresItsPeekAndTab() {
        model.setEnabled(.claudex, false)
        model.setEnabled(.claudex, true)
        XCTAssertFalse(model.peekHint)
        XCTAssertEqual(model.enabledTabs, MainTab.allCases)
    }
}
