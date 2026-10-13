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
        store.openTagForm()
        XCTAssertTrue(store.tagFormOpen)
        XCTAssertFalse(store.canAddNewTag)
        store.saveTagForm() // blank: nothing is created
        XCTAssertTrue(store.customTags.isEmpty)
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertTrue(store.tagMenuOpen)
        store.openTagForm()
        store.newTag = "Design"
        XCTAssertTrue(store.canAddNewTag)
        store.saveTagForm()
        XCTAssertEqual(store.customTags, [CustomTag(id: "design", hex: 0xFFD86B)])
        XCTAssertEqual(store.todoTag, "design")
        XCTAssertEqual(store.newTag, "")
        XCTAssertFalse(store.tagMenuOpen)
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertEqual(store.tagOrder, ["release", "bug", "deps", "docs", "design"])
        for name in ["a", "b", "c", "d", "e", "f"] {
            store.openTagForm()
            store.newTag = name
            store.saveTagForm()
        }
        XCTAssertEqual(store.customTags.map(\.hex), NotesStore.tagPalette + [NotesStore.tagPalette[0]]) // wraps after six
    }

    func testPickedSwatchIsTheNewTagsColour() {
        let store = NotesStore(url: nil)
        store.openTagForm()
        XCTAssertEqual(store.tagHex, NotesStore.tagPalette[0]) // starts on the next colour in turn
        store.newTag = "design"
        store.tagHex = NotesStore.tagPalette[3]
        store.saveTagForm()
        XCTAssertEqual(store.customTags, [CustomTag(id: "design", hex: NotesStore.tagPalette[3])])
        store.openTagForm()
        XCTAssertEqual(store.tagHex, NotesStore.tagPalette[1])
    }

    func testExistingTagIsPickedNotDuplicated() {
        let store = NotesStore(url: nil)
        func add(_ name: String) {
            store.toggleTagMenu()
            store.openTagForm()
            store.newTag = name
            store.saveTagForm()
        }
        add("#BUG")
        XCTAssertEqual(store.todoTag, "bug")
        XCTAssertTrue(store.customTags.isEmpty)
        add("design")
        add("design")
        XCTAssertEqual(store.customTags.count, 1)
    }

    func testFilterMenuNewTagKeepsMenuOpenAndDoesNotPickForTheTodo() {
        let store = NotesStore(url: nil)
        store.toggleFilterMenu()
        store.openTagForm()
        store.newTag = "Design"
        store.saveTagForm()
        XCTAssertEqual(store.customTags.map(\.id), ["design"])
        XCTAssertTrue(store.filterMenuOpen)
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertNil(store.todoTag)
        XCTAssertEqual(store.newTag, "")
    }

    func testOutsideClickClosesBothMenusAndTheForm() {
        let store = NotesStore(url: nil)
        store.toggleFilterMenu()
        store.openTagForm()
        store.newTag = "x"
        store.closeMenus()
        XCTAssertFalse(store.filterMenuOpen)
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertEqual(store.newTag, "")
        store.toggleTagMenu()
        store.closeMenus()
        XCTAssertFalse(store.tagMenuOpen)
        XCTAssertTrue(store.customTags.isEmpty)
    }

    func testBaseAndMiscTagsCannotBeEditedOrDeleted() {
        let store = NotesStore(url: nil)
        XCTAssertFalse(store.canEditTag("bug"))
        XCTAssertFalse(store.canEditTag("misc"))
        XCTAssertTrue(store.canEditTag("design"))
        store.openTagForm(editing: "bug")
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertNil(store.editingTag)
        store.deleteTag("bug")
        XCTAssertEqual(store.todos.filter { $0.tag == "bug" }.count, 1)
    }

    func testEditTagRenamesRecoloursAndMovesTodosAndSelections() {
        let store = NotesStore(url: nil)
        store.openTagForm()
        store.newTag = "design"
        store.saveTagForm()
        store.draft = "Polish #design"
        store.addTodo()
        store.pickFilter("design")
        store.pickTodoTag("design")
        store.openTagForm(editing: "design")
        XCTAssertEqual(store.newTag, "design")
        XCTAssertEqual(store.tagHex, 0xFFD86B)
        store.newTag = " #Look & Feel "
        store.tagHex = 0x8AB4FF
        store.saveTagForm()
        XCTAssertNil(store.editingTag)
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertEqual(store.customTags, [CustomTag(id: "look-feel", hex: 0x8AB4FF)])
        XCTAssertEqual(store.todos[0].tag, "look-feel")
        XCTAssertEqual(store.filterTag, "look-feel")
        XCTAssertEqual(store.todoTag, "look-feel")
        XCTAssertEqual(store.tagOrder.last, "look-feel")
    }

    func testEditingAColourOnlyKeepsTheNameAndATodoOnlyTagGainsAColour() {
        let store = NotesStore(url: nil)
        store.draft = "Polish #design" // `design` lives on the todo only, no CustomTag yet
        store.addTodo()
        XCTAssertNil(store.customColor("design"))
        store.openTagForm(editing: "design")
        store.tagHex = 0xFF8AD8
        store.saveTagForm()
        XCTAssertEqual(store.customTags, [CustomTag(id: "design", hex: 0xFF8AD8)])
        XCTAssertEqual(store.todos[0].tag, "design")
        store.openTagForm(editing: "design")
        store.tagHex = 0x7CE38B
        store.saveTagForm()
        XCTAssertEqual(store.customTags, [CustomTag(id: "design", hex: 0x7CE38B)])
    }

    func testRenameOntoExistingTagMergesAndBlankCancels() {
        let store = NotesStore(url: nil)
        store.openTagForm()
        store.newTag = "design"
        store.saveTagForm()
        store.draft = "Polish #design"
        store.addTodo()
        store.openTagForm(editing: "design")
        store.newTag = "  "
        store.saveTagForm() // blank: nothing changes
        XCTAssertEqual(store.todos[0].tag, "design")
        XCTAssertEqual(store.customTags.count, 1)
        store.openTagForm(editing: "design")
        store.newTag = "bug"
        store.saveTagForm()
        XCTAssertEqual(store.todos[0].tag, "bug")
        XCTAssertTrue(store.customTags.isEmpty)
        XCTAssertEqual(store.count(of: "bug"), 2)
    }

    func testDeleteTagFallsTodosBackToMiscAndResetsSelections() {
        let store = NotesStore(url: nil)
        store.openTagForm()
        store.newTag = "design"
        store.saveTagForm()
        store.draft = "Polish #design"
        store.addTodo()
        store.pickFilter("design")
        store.pickTodoTag("design")
        store.deleteTag("design")
        XCTAssertTrue(store.customTags.isEmpty)
        XCTAssertEqual(store.todos[0].tag, "misc")
        XCTAssertEqual(store.filterTag, "all")
        XCTAssertNil(store.todoTag)
        XCTAssertEqual(store.tagOrder, ["release", "bug", "deps", "docs", "misc"])
    }

    func testCancelTagFormClearsFieldAndGoesBackToTheMenu() {
        let store = NotesStore(url: nil)
        store.toggleTagMenu()
        store.openTagForm()
        store.newTag = "abc"
        store.cancelTagForm()
        XCTAssertEqual(store.newTag, "")
        XCTAssertFalse(store.tagFormOpen)
        XCTAssertTrue(store.tagMenuOpen)
    }

    func testCustomTagsAndTheirColoursSurviveARelaunchAndOldFilesStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)")
        let url = dir.appending(path: "notes.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = NotesStore(url: url)
        first.toggleTagMenu() // from the assign menu, so the new tag is picked for the next todo
        first.openTagForm()
        first.newTag = "design"
        first.tagHex = 0xFFD86B
        first.saveTagForm()
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

    // MARK: Day sections, edit, delete

    private func day(_ offset: Int, of now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -offset, to: now)!
    }

    func testAddTodoStampsCreatedAt() {
        let store = NotesStore(url: nil)
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        store.now = { stamp }
        store.draft = "New"
        store.addTodo()
        XCTAssertEqual(store.todos[0].createdAt, stamp)
    }

    func testSectionsGroupByDayNewestFirstWithUndatedLastAndFollowTheFilter() {
        let now = SampleData.now
        let seed = [TodoSample(id: 1, title: "old", tag: "bug", due: "", createdAt: day(5, of: now)),
                    TodoSample(id: 2, title: "none", tag: "bug", due: ""),
                    TodoSample(id: 3, title: "today-a", tag: "bug", due: "", createdAt: now),
                    TodoSample(id: 4, title: "yday", tag: "docs", due: "", createdAt: day(1, of: now)),
                    TodoSample(id: 5, title: "today-b", tag: "docs", due: "", createdAt: now)]
        let store = NotesStore(url: nil, seed: seed)
        store.now = { now }
        let sections = store.sections
        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", day(5, of: now).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), "Earlier"])
        XCTAssertEqual(sections.map { $0.todos.map(\.id) }, [[3, 5], [4], [1], [2]]) // array order kept inside a day
        store.pickFilter("docs")
        XCTAssertEqual(store.sections.map(\.title), ["Today", "Yesterday"]) // empty days drop out
        XCTAssertEqual(store.sections.map { $0.todos.map(\.id) }, [[5], [4]])
    }

    func testSeedTodosAllLandUnderEarlier() {
        let sections = NotesStore(url: nil).sections
        XCTAssertEqual(sections.map(\.title), ["Earlier"])
        XCTAssertEqual(sections[0].todos.count, SampleData.todos.count)
    }

    func testDeleteThenUndoRestoresPositionAndAddClearsUndo() {
        let store = NotesStore(url: nil)
        store.delete(3)
        XCTAssertEqual(store.todos.map(\.id), [1, 2, 4, 5])
        XCTAssertEqual(store.footer, "Todo deleted")
        store.undo()
        XCTAssertEqual(store.todos.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertNil(store.deleted)
        store.delete(5)
        store.draft = "Fresh"
        store.addTodo() // would reuse id 5; undo must be gone
        XCTAssertNil(store.deleted)
        store.undo()
        XCTAssertEqual(store.todos.filter { $0.id == 5 }.count, 1)
    }

    func testEditChangesOnlyTheTitleAndBlankOrCancelKeepsIt() {
        let store = NotesStore(url: nil)
        store.startEdit(1)
        XCTAssertEqual(store.editId, 1)
        XCTAssertEqual(store.editDraft, "Ship TestFlight build 2.4.0")
        store.editDraft = "  Ship 2.5  "
        store.saveEdit()
        XCTAssertNil(store.editId)
        XCTAssertEqual(store.todos[0].title, "Ship 2.5")
        XCTAssertEqual(store.todos[0].tag, "release")
        XCTAssertTrue(store.todos[0].hot)
        store.startEdit(1)
        store.editDraft = "   "
        store.saveEdit()
        XCTAssertEqual(store.todos[0].title, "Ship 2.5")
        store.startEdit(1)
        store.editDraft = "nope"
        store.cancelEdit()
        XCTAssertEqual(store.todos[0].title, "Ship 2.5")
    }

    func testResetTransientDropsEditAndUndo() {
        let store = NotesStore(url: nil)
        store.delete(1)
        store.startEdit(2)
        store.resetTransient()
        XCTAssertNil(store.editId)
        XCTAssertNil(store.deleted)
    }

    func testEditDeleteAndCreatedAtSurviveARelaunch() {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes-\(UUID().uuidString)/notes.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = NotesStore(url: url)
        first.draft = "Dated"
        first.addTodo()
        first.delete(2)
        first.startEdit(1)
        first.editDraft = "Renamed"
        first.saveEdit()
        let second = NotesStore(url: url)
        XCTAssertEqual(second.todos.map(\.id), first.todos.map(\.id))
        XCTAssertFalse(second.todos.contains { $0.id == 2 })
        XCTAssertEqual(second.todos.first { $0.id == 1 }?.title, "Renamed")
        XCTAssertNotNil(second.todos[0].createdAt)
    }

    func testNotchModelPendingUndoFollowsTheVisibleTab() {
        let model = NotchModel(sample: true)
        XCTAssertNil(model.pendingUndo)
        model.notes.delete(1)
        XCTAssertNotNil(model.pendingUndo)
        model.setNotesTab(.commands) // a tab switch drops every pending undo
        XCTAssertNil(model.pendingUndo)
        model.commands.delete(1)
        XCTAssertNotNil(model.pendingUndo) // commands' own undo
        model.setNotesTab(.todo)
        XCTAssertNil(model.pendingUndo)
    }
}
