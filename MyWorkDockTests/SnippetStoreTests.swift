import XCTest
@testable import MyWorkDock

@MainActor
final class SnippetStoreTests: XCTestCase {
    func testAddTrimsPrependsAndIgnoresBlank() {
        let store = SnippetStore(.commands, url: nil, seed: ["a"])
        store.draft = "  "
        store.add()
        XCTAssertEqual(store.items.count, 1)
        store.draft = " ls -la "
        store.add()
        XCTAssertEqual(store.items.map(\.text), ["ls -la", "a"])
        XCTAssertEqual(store.draft, "")
    }

    func testEditSavesOrCancelsOnEmpty() {
        let store = SnippetStore(.commands, url: nil, seed: ["a", "b"])
        store.startEdit(2)
        store.editDraft = "bb"
        store.saveEdit()
        XCTAssertEqual(store.items.map(\.text), ["a", "bb"])
        XCTAssertNil(store.editId)
        store.startEdit(1)
        store.editDraft = "  "
        store.saveEdit()
        XCTAssertEqual(store.items[0].text, "a")
    }

    func testDeleteThenUndoRestoresPositionAndAddClearsUndo() {
        let store = SnippetStore(.commands, url: nil, seed: ["a", "b", "c"])
        store.delete(2)
        XCTAssertEqual(store.items.map(\.text), ["a", "c"])
        XCTAssertEqual(store.footer, "Command deleted")
        store.undo()
        XCTAssertEqual(store.items.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(store.footer, "3 saved commands")
        store.delete(3)
        store.draft = "d"
        store.add()
        XCTAssertNil(store.deleted)
    }

    func testCopyWritesTextAndShowsCopiedFooter() {
        let store = SnippetStore(.commands, url: nil, seed: ["a"])
        var copied = ""
        store.copyToClipboard = { copied = $0 }
        store.copy(1)
        XCTAssertEqual(copied, "a")
        XCTAssertEqual(store.footer, "Copied to clipboard")
    }

    func testCopyNotifiesOnCopied() {
        let store = SnippetStore(.commands, url: nil, seed: ["a"])
        var count = 0
        store.copyToClipboard = { _ in }
        store.onCopied = { count += 1 }
        store.copy(1)
        XCTAssertEqual(count, 1)
    }

    func testPromptsUseTheirOwnNounsAndSeed() {
        let store = SnippetStore.sample(.prompts)
        XCTAssertEqual(store.items.count, 5)
        XCTAssertEqual(store.footer, "5 saved prompts")
        store.delete(1)
        XCTAssertEqual(store.footer, "Prompt deleted")
        XCTAssertEqual(SnippetStore.sample(.commands).items.count, 6)
    }

    func testResetDropsEditDraftUndoAndCopied() {
        let store = SnippetStore(.prompts, url: nil, seed: ["a", "b"])
        store.draft = "x"
        store.startEdit(1)
        store.delete(2)
        store.showCopied(1)
        store.reset()
        XCTAssertEqual(store.draft, "")
        XCTAssertNil(store.editId)
        XCTAssertNil(store.deleted)
        XCTAssertNil(store.copiedId)
        XCTAssertEqual(store.items.map(\.text), ["a"])
    }

    func testChangesSurviveARelaunch() {
        let url = FileManager.default.temporaryDirectory.appending(path: "snips-\(UUID().uuidString)/prompts.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = SnippetStore(.prompts, url: url, seed: ["a"])
        first.draft = "b"
        first.add()
        XCTAssertEqual(SnippetStore(.prompts, url: url, seed: []).items.map(\.text), ["b", "a"])
    }

    func testSearchFiltersByTextIgnoringCaseAndSpacesAndKeepsOrder() {
        let store = SnippetStore(.prompts, url: nil, seed: ["Write release notes", "Review this PR", "Release checklist", "Explain a crash"])
        XCTAssertFalse(store.isSearching)
        XCTAssertEqual(store.foundText, "")
        store.openSearch()
        store.query = "  RELEASE "
        XCTAssertEqual(store.visibleItems.map(\.text), ["Write release notes", "Release checklist"])
        XCTAssertEqual(store.foundText, "2 found")
        XCTAssertEqual(store.footer, "2 of 4 prompts shown")
        store.query = "zzz"
        XCTAssertTrue(store.visibleItems.isEmpty)
        XCTAssertEqual(store.foundText, "0 found")
        XCTAssertEqual(store.emptyText, "No prompts match “zzz”.")
        XCTAssertEqual(store.footer, "0 of 4 prompts shown")
        store.closeSearch()
        XCTAssertEqual(store.visibleItems.count, 4)
        XCTAssertFalse(store.searchOpen)
        XCTAssertEqual(store.footer, "4 saved prompts")
    }

    func testDeletedAndCopiedFootersWinOverTheSearchFooter() {
        let store = SnippetStore(.prompts, url: nil, seed: ["alpha", "beta"])
        store.query = "alpha"
        store.delete(1)
        XCTAssertEqual(store.footer, "Prompt deleted")
        store.undo()
        store.showCopied(1)
        XCTAssertEqual(store.footer, "Copied to clipboard")
    }

    func testDeleteUndoAndEditWorkOnTheFullListWhileFiltered() {
        let store = SnippetStore(.prompts, url: nil, seed: ["a one", "b two", "a three"])
        store.query = "a "
        XCTAssertEqual(store.visibleItems.map(\.id), [1, 3])
        store.delete(3)
        XCTAssertEqual(store.items.map(\.id), [1, 2])
        store.undo()
        XCTAssertEqual(store.items.map(\.id), [1, 2, 3]) // back at its original place, not the filtered one
    }

    func testEmptyListHasItsOwnText() {
        let commands = SnippetStore(.commands, url: nil, seed: [])
        let prompts = SnippetStore(.prompts, url: nil, seed: [])
        XCTAssertTrue(commands.items.isEmpty)
        XCTAssertEqual(commands.kind.emptyTitle, "No commands saved yet")
        XCTAssertEqual(commands.kind.emptyHint, "Type or paste a command above, then press Enter.")
        XCTAssertEqual(prompts.kind.emptyTitle, "No prompts saved yet")
        XCTAssertEqual(prompts.kind.emptyHint, "Write a prompt above, then press Enter.")
        XCTAssertEqual(commands.footer, "0 saved commands")
    }

    func testLinksAreSingleLineAndKeepTheirOwnFileAndTexts() {
        let store = SnippetStore(.links, url: nil, seed: [])
        store.draft = "  https://example.com/a\n  b  "
        store.add()
        XCTAssertEqual(store.items.map(\.text), ["https://example.com/ab"])
        store.startEdit(1)
        store.editDraft = "example.com/x y"
        store.saveEdit()
        XCTAssertEqual(store.items[0].text, "example.com/xy")
        XCTAssertEqual(store.kind.file, "links.json")
        XCTAssertEqual(store.kind.emptyTitle, "No links saved yet")
        XCTAssertEqual(store.footer, "1 saved links")
    }

    func testOpenUsesTheSavedLinkAndAddsHttpsWhenThereIsNoScheme() {
        let store = SnippetStore(.links, url: nil, seed: ["example.com/a", "obsidian://open?vault=x", "https://swift.org"])
        var opened: [URL] = []
        store.openURL = { opened.append($0) }
        store.open(1)
        store.open(2)
        store.open(3)
        store.open(99) // unknown id: nothing
        XCTAssertEqual(opened.map(\.absoluteString), ["https://example.com/a", "obsidian://open?vault=x", "https://swift.org"])
        XCTAssertNil(SnippetStore.url(from: "   "))
    }

    func testSubTabSwitchResetClosesTheSearch() {
        let store = SnippetStore.sample(.prompts)
        store.openSearch()
        store.query = "release"
        store.reset()
        XCTAssertFalse(store.searchOpen)
        XCTAssertEqual(store.query, "")
    }

    func testDoubleClickCopiesWithoutHintAndSingleClickShowsThenHidesTheHint() async {
        let store = SnippetStore(.commands, url: nil, seed: ["a"])
        var written = ""
        store.copyToClipboard = { written = $0 }
        store.pause = { _ in }

        store.tap(1) // two clicks before the double-click interval ends
        store.tap(1)
        await Task.yield() // lets the cancelled first sequence finish
        XCTAssertEqual(written, "a")
        XCTAssertFalse(store.hintShown)

        var seen: [(TimeInterval, Bool)] = []
        store.pause = { d in seen.append((d, store.hintShown)) }
        await store.tap(1)?.value // one click, no second one
        XCTAssertEqual(seen.map(\.0), [store.doubleClickInterval, SnippetStore.hintTime])
        XCTAssertEqual(seen.map(\.1), [false, true]) // hint is up while the second wait runs
        XCTAssertFalse(store.hintShown) // and gone after it
    }
}
