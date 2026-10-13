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

    func testPeekHugsItsEarsAroundTheCentredKeepOut() {
        model.pointer(inside: true)
        let g = model.geometry, e = model.peekExtents
        XCTAssertEqual(g.width, Geo.keepOutWidth + e.left + e.right)
        XCTAssertEqual(g.centerOffset, (e.right - e.left) / 2)
        // The shell's left edge sits `left + 100` pt from the hardware-notch centre.
        XCTAssertEqual(g.centerOffset - g.width / 2, -(e.left + Geo.keepOutWidth / 2))
    }
}
