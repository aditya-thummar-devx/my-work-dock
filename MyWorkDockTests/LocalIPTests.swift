import XCTest
@testable import MyWorkDock

@MainActor
final class LocalIPTests: XCTestCase {
    func testPrefersEn0ElseFirstPrivateElseNone() {
        XCTAssertEqual(LocalIP.pick(from: [("utun3", "10.8.0.2"), ("en0", "169.254.3.4"), ("en5", "192.168.9.9")]), "169.254.3.4")
        XCTAssertEqual(LocalIP.pick(from: [("utun3", "100.64.0.1"), ("en5", "172.20.1.1"), ("bridge0", "10.0.0.5")]), "172.20.1.1")
        XCTAssertNil(LocalIP.pick(from: [("utun3", "100.64.0.1"), ("en7", "8.8.8.8")]))
        XCTAssertNil(LocalIP.pick(from: []))
    }

    func testPrivateRanges() {
        for ip in ["10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.255", "192.168.0.1"] { XCTAssertTrue(LocalIP.isPrivate(ip), ip) }
        for ip in ["172.15.0.1", "172.32.0.1", "192.169.0.1", "11.0.0.1", "100.64.0.1", "not an ip", "192.168.1"] { XCTAssertFalse(LocalIP.isPrivate(ip), ip) }
    }

    func testCurrentReturnsNilOrAValidAddress() {
        if let ip = LocalIP.current() { XCTAssertEqual(ip.split(separator: ".").count, 4) }
    }

    /// Click: idle → busy (spinner) → re-read → clipboard → copied → idle; the second pause sees `.copied`.
    func testClickSequenceReReadsCopiesAndReturnsToIdle() async {
        var current = "192.168.1.24"
        let store = LocalIPStore(read: { current })
        var copied: [String] = []
        var seen: [LocalIPStore.Phase] = []
        store.copyToClipboard = { copied.append($0) }
        store.pause = { _ in seen.append(store.phase) }
        XCTAssertEqual(store.ip, "192.168.1.24")
        current = "192.168.1.31"
        await store.click()?.value
        XCTAssertEqual(seen, [.busy, .copied])
        XCTAssertEqual(copied, ["192.168.1.31"])
        XCTAssertEqual(store.ip, "192.168.1.31")
        XCTAssertEqual(store.phase, .idle)
    }

    func testTimingsAreTheSpec() {
        XCTAssertEqual(LocalIPStore.spinnerTime, 0.55)
        XCTAssertEqual(LocalIPStore.copiedTime, 1.5)
    }

    func testNoNetworkDisablesTheClickAndRefreshRecovers() async {
        var current: String?
        let store = LocalIPStore(read: { current })
        store.pause = { _ in }
        XCTAssertNil(store.ip)
        XCTAssertNil(store.click())
        XCTAssertEqual(store.phase, .idle)
        current = "10.0.0.7"
        store.refresh() // panel open / network change
        XCTAssertEqual(store.ip, "10.0.0.7")
        XCTAssertNotNil(store.click())
    }

    func testClickIsIgnoredWhileBusyAndRefreshDoesNotTouchABusyChip() async {
        var current = "192.168.1.24"
        let store = LocalIPStore(read: { current })
        var gate: CheckedContinuation<Void, Never>?
        store.pause = { _ in await withCheckedContinuation { gate = $0 } }
        let run = store.click()
        await Task.yield()
        XCTAssertEqual(store.phase, .busy)
        XCTAssertNil(store.click())
        current = "10.1.1.1"
        store.refresh()
        XCTAssertEqual(store.ip, "192.168.1.24")
        store.pause = { _ in }
        gate?.resume()
        await run?.value
        XCTAssertEqual(store.ip, "10.1.1.1") // the click's own re-read
    }

    func testNetworkLostDuringTheClickEndsIdleWithoutCopying() async {
        var current: String? = "192.168.1.24"
        let store = LocalIPStore(read: { current })
        var copied = 0
        store.copyToClipboard = { _ in copied += 1 }
        store.pause = { _ in current = nil }
        await store.click()?.value
        XCTAssertNil(store.ip)
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(copied, 0)
    }

    func testOpeningThePanelRefreshesTheAddress() {
        let model = NotchModel(sample: true)
        XCTAssertEqual(model.localIP.ip, "192.168.1.24")
        model.localIP.read = { "10.0.0.9" }
        model.openPanel()
        XCTAssertEqual(model.localIP.ip, "10.0.0.9")
    }
}
