import XCTest
@testable import MyWorkDock

@MainActor
final class ClipboardStoreTests: XCTestCase {
    /// A store wired to a fake pasteboard: set `pb.text` / `pb.app`, bump `pb.count`, then `poll()`.
    final class Pasteboard { var count = 0, text: String?, app: String? }

    private func make(url: URL? = nil, excluded: Set<String> = ["pw.manager"]) -> (ClipboardStore, Pasteboard) {
        let pb = Pasteboard()
        let store = ClipboardStore(url: url, excluded: excluded, changeCount: { pb.count }, readText: { pb.text }, frontApp: { pb.app })
        return (store, pb)
    }

    private func copy(_ text: String?, app: String? = nil, _ store: ClipboardStore, _ pb: Pasteboard) {
        pb.count += 1
        pb.text = text
        pb.app = app
        store.poll()
    }

    func testRecordsNewestFirstAndMovesRepeatToTopKeepingItsPin() {
        let (store, pb) = make()
        copy("a", store, pb)
        copy("b", store, pb)
        XCTAssertEqual(store.items.map(\.text), ["b", "a"])
        store.togglePin(store.items[1].id)
        copy("a", store, pb)
        XCTAssertEqual(store.items.map(\.text), ["a", "b"])
        XCTAssertTrue(store.items[0].pinned)
    }

    func testSameTextWithDifferentWhitespaceIsNotAddedTwice() {
        let (store, pb) = make()
        copy("foo", store, pb)
        copy("bar", store, pb)
        copy("foo\n", store, pb)
        copy("  bar ", store, pb)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), ["  bar ", "foo\n"]) // newest copy wins, back on top
    }

    func testIgnoresUnchangedPasteboardBlankHugeSecretAndExcludedApps() {
        let (store, pb) = make()
        copy("a", store, pb)
        store.poll() // same changeCount: nothing read
        pb.text = "never read"
        store.poll()
        copy("  \n", store, pb)
        copy(String(repeating: "x", count: ClipboardStore.maxChars + 1), store, pb)
        copy(nil, store, pb) // concealed or non-text
        copy("hunter2", app: "pw.manager", store, pb)
        XCTAssertEqual(store.items.map(\.text), ["a"])
    }

    func testLimitCountsOnlyUntaggedUnpinnedClipsAndNeverDropsTheRest() {
        let (store, pb) = make()
        store.setLimit(3)
        copy("pinned", store, pb)
        store.togglePin(store.items[0].id)
        store.openTagManage()
        makeTag("keep", store)
        for i in 0..<10 { // far more tagged clips than the limit: all stay
            copy("tagged \(i)", store, pb)
            store.assign("keep", to: store.items[0].id)
        }
        for i in 0..<6 { copy("c\(i)", store, pb) }
        XCTAssertEqual(store.items.count, 1 + 10 + 3)
        XCTAssertEqual(store.items.filter { $0.tag == nil && !$0.pinned }.map(\.text), ["c5", "c4", "c3"])
        XCTAssertTrue(store.items.contains { $0.text == "pinned" })
        XCTAssertEqual(store.items.filter { $0.tag == "keep" }.count, 10)
    }

    func testSetLimitClampsTrimsOldestAndIsSaved() {
        let url = FileManager.default.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (store, pb) = make(url: url)
        XCTAssertEqual(store.limit, ClipboardStore.defaultLimit)
        for i in 0..<5 { copy("c\(i)", store, pb) }
        XCTAssertEqual(store.removalCount(at: 2), 3)
        XCTAssertEqual(store.removalCount(at: 50), 0)
        store.setLimit(2)
        XCTAssertEqual(store.items.map(\.text), ["c4", "c3"])
        store.setLimit(0)
        XCTAssertEqual(store.limit, 1)
        XCTAssertEqual(store.items.map(\.text), ["c4"])
        store.setLimit(5000)
        XCTAssertEqual(store.limit, ClipboardStore.maxLimit)
        XCTAssertEqual(ClipboardStore.maxLimit, 1000)
        store.setLimit(7)
        let (again, _) = make(url: url)
        XCTAssertEqual(again.limit, 7)
    }

    func testVisibleItemsPutPinnedFirstAndFilterBySearch() {
        let (store, pb) = make()
        copy("apple", store, pb)
        copy("banana", store, pb)
        copy("apricot", store, pb)
        store.togglePin(store.items.first { $0.text == "apple" }!.id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["apple", "apricot", "banana"])
        store.query = " AP "
        XCTAssertEqual(store.visibleItems.map(\.text), ["apple", "apricot"])
        XCTAssertEqual(store.foundText, "2 found")
        store.closeSearch()
        XCTAssertEqual(store.query, "")
    }

    func testCopyWritesTextAndIsNotRecordedAgain() {
        let (store, pb) = make()
        copy("a", store, pb)
        copy("b", store, pb)
        var written = ""
        store.copyToClipboard = { written = $0; pb.count += 1; pb.text = $0 }
        store.copy(store.items[1].id)
        store.poll()
        XCTAssertEqual(written, "a")
        XCTAssertEqual(store.items.map(\.text), ["b", "a"]) // "a" did not jump to the top
        XCTAssertEqual(store.footer, "Copied to clipboard")
    }

    func testDoubleClickCopiesWithoutHintAndSingleClickShowsThenHidesTheHint() async {
        let (store, pb) = make()
        copy("a", store, pb)
        var written = ""
        store.copyToClipboard = { written = $0 }
        store.pause = { _ in }
        let id = store.items[0].id

        store.tap(id) // two clicks before the double-click interval ends
        store.tap(id)
        await Task.yield()
        XCTAssertEqual(written, "a")
        XCTAssertFalse(store.hintShown)

        var seen: [(TimeInterval, Bool)] = []
        store.pause = { d in seen.append((d, store.hintShown)) }
        await store.tap(id)?.value // one click, no second one
        XCTAssertEqual(seen.map(\.0), [store.doubleClickInterval, ClipboardStore.hintTime])
        XCTAssertEqual(seen.map(\.1), [false, true]) // hint is up while the second wait runs
        XCTAssertFalse(store.hintShown) // and gone after it
    }

    /// `New tag` popup: name + colour.
    private func makeTag(_ name: String, hex: UInt32 = 0x123456, _ store: ClipboardStore) {
        store.openTagForm()
        store.newTag = name
        store.tagHex = hex
        store.saveTagForm()
    }

    func testNewTagFromAClipMenuIsAssignedAndKeepsItsColourAcrossRecopyAndRelaunch() {
        let url = FileManager.default.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (store, pb) = make(url: url)
        copy("a", store, pb)
        copy("b", store, pb)
        let a = store.items[1].id
        store.openTagPicker(a)
        makeTag("  #Work Items ", hex: 0xAABBCC, store) // opened from the assign menu: the clip gets it
        XCTAssertFalse(store.tagMenuOpen)
        XCTAssertEqual(store.items.first { $0.id == a }?.tag, "work-items")
        XCTAssertEqual(store.tags, ["work-items"])
        XCTAssertEqual(store.customTags, [CustomTag(id: "work-items", hex: 0xAABBCC)])
        store.openTagPicker(a)
        store.openTagForm()
        store.newTag = " # " // blank name: popup closes, nothing is created
        XCTAssertFalse(store.canAddNewTag)
        store.saveTagForm()
        XCTAssertEqual(store.tags, ["work-items"])
        copy("a", store, pb) // copying it again keeps the tag
        XCTAssertEqual(store.items[0].tag, "work-items")
        let (again, _) = make(url: url)
        XCTAssertEqual(again.items.map(\.tag), ["work-items", nil])
        XCTAssertEqual(again.customTags, store.customTags)
    }

    func testManageEditRenamesRecoloursMergesAndDeletes() {
        let (store, pb) = make()
        copy("a", store, pb)
        copy("b", store, pb)
        let (a, b) = (store.items[1].id, store.items[0].id)
        store.openTagManage()
        makeTag("one", hex: 0x111111, store) // from the manage list: created, not assigned
        makeTag("two", hex: 0x222222, store)
        XCTAssertTrue(store.tagManageOpen)
        XCTAssertEqual(store.tags, ["one", "two"])
        XCTAssertNil(store.items[0].tag)
        store.assign("one", to: a)
        store.assign("two", to: b)

        store.openTagForm(editing: "one") // rename + recolour: clips follow
        XCTAssertEqual(store.newTag, "one")
        XCTAssertEqual(store.tagHex, 0x111111)
        store.newTag = "uno"
        store.tagHex = 0x333333
        store.saveTagForm()
        XCTAssertEqual(store.tags, ["uno", "two"])
        XCTAssertEqual(store.customTags.first?.hex, 0x333333)
        XCTAssertEqual(store.items.first { $0.id == a }?.tag, "uno")

        store.pickFilter("two")
        store.openTagForm(editing: "two") // an existing name merges the two tags
        store.newTag = "uno"
        store.saveTagForm()
        XCTAssertEqual(store.tags, ["uno"])
        XCTAssertEqual(store.customTags.first?.hex, 0x333333) // the surviving tag keeps its colour
        XCTAssertEqual(store.items.map(\.tag), ["uno", "uno"])
        XCTAssertEqual(store.filterTag, "uno") // a filter on the renamed tag follows it

        store.deleteTag("uno")
        XCTAssertTrue(store.tags.isEmpty)
        XCTAssertEqual(store.items.map(\.tag), [nil, nil])
        XCTAssertNil(store.filterTag)
    }

    func testTagFilterCombinesWithSearchAndStaysOnAnEmptyTag() {
        let (store, pb) = make()
        copy("apple", store, pb)
        copy("apricot", store, pb)
        copy("banana", store, pb)
        makeTag("fruit", store)
        for item in store.items where item.text != "banana" { store.assign("fruit", to: item.id) }
        store.pickFilter("fruit")
        XCTAssertEqual(store.visibleItems.map(\.text), ["apricot", "apple"])
        store.query = "apple"
        XCTAssertEqual(store.visibleItems.map(\.text), ["apple"])
        XCTAssertEqual(store.footer, "1 of 3 clips shown")
        store.clearFilters()
        XCTAssertNil(store.filterTag)
        XCTAssertEqual(store.query, "")
        store.pickFilter("fruit")
        store.pickFilter("fruit") // same chip again clears
        XCTAssertNil(store.filterTag)
        store.pickFilter("fruit")
        for item in store.items { store.assign(nil, to: item.id) }
        XCTAssertEqual(store.tags, ["fruit"]) // the tag outlives its clips
        XCTAssertEqual(store.filterTag, "fruit")
        XCTAssertTrue(store.visibleItems.isEmpty)
        XCTAssertEqual(store.emptyText, "No clips tagged #fruit.")
    }

    func testTagsFromBeforeColoursGetOneAndAreSavedWithIt() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"[{"id":1,"text":"a","pinned":false,"tag":"zed"},{"id":2,"text":"b","pinned":false,"tag":"abc"}]"#.utf8).write(to: url)
        let (store, pb) = make(url: url)
        XCTAssertEqual(store.tags, ["abc", "zed"])
        XCTAssertTrue(store.tags.allSatisfy { store.customColor($0) != nil })
        copy("c", store, pb) // the next save writes the new format
        let (again, _) = make(url: url)
        XCTAssertEqual(again.customTags, store.customTags)
        XCTAssertEqual(again.items.count, 3)
    }

    func testHistorySavedBeforeTagsStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"[{"id":1,"text":"old","pinned":true}]"#.utf8).write(to: url)
        let (store, _) = make(url: url)
        XCTAssertEqual(store.items, [ClipItem(id: 1, text: "old", pinned: true)])
    }

    func testDeleteAndSurvivesRelaunch() {
        let url = FileManager.default.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let (store, pb) = make(url: url)
        copy("a", store, pb)
        copy("b", store, pb)
        store.delete(store.items[0].id)
        let (again, _) = make(url: url)
        XCTAssertEqual(again.items.map(\.text), ["a"])
    }
}
