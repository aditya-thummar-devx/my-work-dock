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

    func testSubTabSwitchResetClosesTheSearch() {
        let store = SnippetStore.sample(.prompts)
        store.openSearch()
        store.query = "release"
        store.reset()
        XCTAssertFalse(store.searchOpen)
        XCTAssertEqual(store.query, "")
    }
}
