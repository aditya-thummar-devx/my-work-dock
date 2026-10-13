import XCTest
@testable import MyWorkDock

@MainActor
final class NotesStoreTests: XCTestCase {
    func testAddTodoTakesFirstTagStripsAllTagsAndPrepends() {
        let store = NotesStore(url: nil)
        store.draft = "Fix login #Bug crash #urgent"
        store.addTodo()
        let first = store.todos[0]
        XCTAssertEqual(first.tag, "bug")
        XCTAssertEqual(first.title, "Fix login  crash") // prototype only trims the ends, inner gaps stay
        XCTAssertEqual(first.due, "Today")
        XCTAssertEqual(store.draft, "")
        XCTAssertEqual(store.todos.count, SampleData.todos.count + 1)
    }

    func testAddTodoDefaultsToMiscIgnoresBlankAndKeepsTagOnlyDraftAsTitle() {
        let store = NotesStore(url: nil)
        store.draft = "   "
        store.addTodo()
        XCTAssertEqual(store.todos.count, SampleData.todos.count)
        store.draft = "Write docs"
        store.addTodo()
        XCTAssertEqual(store.todos[0].tag, "misc")
        store.draft = "#idea"
        store.addTodo()
        XCTAssertEqual(store.todos[0].title, "#idea")
        XCTAssertEqual(store.todos[0].tag, "idea")
    }

    func testToggleAndCounts() {
        let store = NotesStore(url: nil)
        XCTAssertEqual(store.leftCount, 3)
        XCTAssertEqual(store.doneCount, 2)
        store.toggle(1)
        XCTAssertEqual(store.leftCount, 2)
        store.toggle(4)
        XCTAssertEqual(store.leftCount, 3)
    }

    func testFooter() {
        XCTAssertEqual(NotesStore(url: nil).footer, "3 left · 2 done")
    }

    func testChangesSurviveARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)/notes.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = NotesStore(url: url)
        first.draft = "Ship it #release"
        first.addTodo()
        first.toggle(1)
        let second = NotesStore(url: url)
        XCTAssertEqual(second.todos.map(\.title), first.todos.map(\.title))
        XCTAssertEqual(second.todos.first { $0.id == 1 }?.done, true)
    }

    /// v1 `notes.json` also carries the deleted Tagged notes; the todos must still load and the next save drops them.
    func testV1FileWithTaggedNotesStillLoadsTodos() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
        let url = dir.appending(path: "notes.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let v1 = #"{"todos":[{"id":7,"title":"Old","tag":"bug","due":"Today","hot":false,"done":false}],"notes":[{"tag":"bug","when":"2h","title":"t","body":"b"}]}"#
        try v1.write(to: url, atomically: true, encoding: .utf8)
        let store = NotesStore(url: url)
        XCTAssertEqual(store.todos.map(\.title), ["Old"])
        store.toggle(7)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("\"notes\""))
    }

    func testTagResolutionTextThenPickedThenMisc() {
        let store = NotesStore(url: nil)
        store.pickTodoTag("idea")
        store.draft = "Fix crash #bug"
        store.addTodo()
        XCTAssertEqual(store.todos[0].tag, "bug")
        store.draft = "Plain text"
        store.addTodo()
        XCTAssertEqual(store.todos[0].tag, "idea")
        store.pickTodoTag(nil)
        store.draft = "No tag"
        store.addTodo()
        XCTAssertEqual(store.todos[0].tag, "misc")
        XCTAssertEqual(store.tagOrder, ["release", "bug", "deps", "docs", "misc", "idea"])
    }

    func testSearchMatchesTitleOrTagAndFilterNarrows() {
        let store = NotesStore(url: nil)
        store.query = " POD "
        XCTAssertEqual(store.visibleTodos.map(\.id), [3])
        XCTAssertEqual(store.foundText, "1 found")
        XCTAssertEqual(store.footer, "1 of 5 shown · 3 left")
        store.query = "bug" // matches the tag, not a title
        XCTAssertEqual(store.visibleTodos.map(\.id), [2])
        store.query = ""
        store.pickFilter("release")
        XCTAssertEqual(store.visibleTodos.map(\.id), [1, 4])
        store.query = "ship"
        XCTAssertEqual(store.visibleTodos.map(\.id), [1])
        XCTAssertEqual(store.emptyWhat, "#release + “ship”")
    }

    func testEmptyStateAndClear() {
        let store = NotesStore(url: nil)
        XCTAssertEqual(store.emptyWhat, "this view")
        store.openSearch()
        store.query = "zzz"
        XCTAssertTrue(store.visibleTodos.isEmpty)
        XCTAssertEqual(store.foundText, "0 found")
        XCTAssertEqual(store.footer, "0 of 5 shown · 3 left")
        store.pickFilter("bug")
        store.clearFilters()
        XCTAssertEqual(store.visibleTodos.count, 5)
        XCTAssertFalse(store.searchOpen)
        XCTAssertEqual(store.query, "")
        XCTAssertEqual(store.footer, "3 left · 2 done")
    }

    func testMenusAreExclusiveAndSubTabSwitchResetsSearchAndMenus() {
        let model = NotchModel(sample: true)
        let store = model.notes
        store.toggleTagMenu()
        store.toggleFilterMenu()
        XCTAssertFalse(store.tagMenuOpen)
        XCTAssertTrue(store.filterMenuOpen)
        model.openSearch()
        store.query = "pod"
        store.pickTodoTag("bug")
        store.pickFilter("deps")
        store.toggleFilterMenu()
        model.setNotesTab(.commands)
        XCTAssertFalse(store.searchOpen)
        XCTAssertFalse(store.filterMenuOpen)
        XCTAssertEqual(store.query, "")
        XCTAssertEqual(store.todoTag, "bug") // picked tag and filter survive, like the prototype
        XCTAssertEqual(store.filterTag, "deps")
        model.openSearch() // ⌘F does nothing on Commands
        XCTAssertFalse(store.searchOpen)
        XCTAssertFalse(model.commands.searchOpen)
        XCTAssertFalse(model.prompts.searchOpen)
        model.setNotesTab(.prompts)
        model.openSearch() // …and opens the Prompts search there
        XCTAssertTrue(model.prompts.searchOpen)
        XCTAssertFalse(store.searchOpen)
        model.setNotesTab(.todo)
        XCTAssertFalse(model.prompts.searchOpen) // a sub-tab switch resets it
    }

    func testCleanTagMatchesThePrototype() {
        XCTAssertEqual(NotesStore.cleanTag("  ##Design System "), "design-system")
        XCTAssertEqual(NotesStore.cleanTag("a!!b__c"), "a-b__c")
        XCTAssertEqual(NotesStore.cleanTag("---x---"), "x")
        XCTAssertEqual(NotesStore.cleanTag("#"), "")
        XCTAssertEqual(NotesStore.cleanTag(String(repeating: "a", count: 30)).count, 20)
    }

    func testNewTagCreatesPicksClosesAndRoundRobinsColours() {
        let store = NotesStore(url: nil)
        store.toggleTagMenu()
        XCTAssertFalse(store.canAddNewTag)
        store.addNewTag() // blank: nothing happens, menu stays
        XCTAssertTrue(store.tagMenuOpen)
        store.newTag = "Design"
        XCTAssertTrue(store.canAddNewTag)
        store.addNewTag()
        XCTAssertEqual(store.customTags, [CustomTag(id: "design", hex: 0xFFD86B)])
        XCTAssertEqual(store.todoTag, "design")
        XCTAssertEqual(store.newTag, "")
        XCTAssertFalse(store.tagMenuOpen)
        XCTAssertEqual(store.tagOrder, ["release", "bug", "deps", "docs", "design"])
        for name in ["a", "b", "c", "d", "e", "f"] {
            store.newTag = name
            store.addNewTag()
        }
        XCTAssertEqual(store.customTags.map(\.hex), NotesStore.tagPalette + [NotesStore.tagPalette[0]]) // wraps after six
    }

    func testExistingTagIsPickedNotDuplicated() {
        let store = NotesStore(url: nil)
        store.newTag = "#BUG"
        store.addNewTag()
        XCTAssertEqual(store.todoTag, "bug")
        XCTAssertTrue(store.customTags.isEmpty)
        store.newTag = "design"
        store.addNewTag()
        store.newTag = "design"
        store.addNewTag()
        XCTAssertEqual(store.customTags.count, 1)
    }

    func testCancelNewTagClearsFieldAndClosesMenu() {
        let store = NotesStore(url: nil)
        store.toggleTagMenu()
        store.newTag = "abc"
        store.cancelNewTag()
        XCTAssertEqual(store.newTag, "")
        XCTAssertFalse(store.tagMenuOpen)
    }

    func testCustomTagsAndTheirColoursSurviveARelaunchAndOldFilesStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
        let url = dir.appending(path: "notes.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = NotesStore(url: url)
        first.newTag = "design"
        first.addNewTag()
        first.draft = "Polish"
        first.addTodo()
        let second = NotesStore(url: url)
        XCTAssertEqual(second.customTags, [CustomTag(id: "design", hex: 0xFFD86B)])
        XCTAssertEqual(second.todos[0].tag, "design")
        XCTAssertNotNil(second.customColor("design"))
        XCTAssertNil(second.customColor("bug"))
        // A file from before custom tags: no `customTags` key.
        let old = #"{"todos":[{"id":1,"title":"Old","tag":"bug","due":"Today","hot":false,"done":false}]}"#
        try old.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(NotesStore(url: url).todos.map(\.title), ["Old"])
        XCTAssertTrue(NotesStore(url: url).customTags.isEmpty)
    }
}
