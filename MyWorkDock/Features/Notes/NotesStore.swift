import SwiftUI
import Observation

/// A tag created with `New tag`: name and the colour it was given.
struct CustomTag: Codable, Equatable {
    var id: String
    var hex: UInt32
}

/// One day's todos under its heading in the TODO list.
struct TodoSection: Identifiable {
    var id: String { title }
    var title: String
    var todos: [TodoSample]
}

/// Todos and the tags the user created, saved as JSON in Application Support after every change.
/// `url == nil` keeps everything in memory (snapshots, tests).
@MainActor @Observable
final class NotesStore {
    private(set) var todos: [TodoSample]
    /// Quick-add text; survives tab switches like the prototype's `draft`, never saved.
    var draft = ""
    /// Why the last save failed; shown in the footer.
    private(set) var saveError: String?

    // UI state, never saved. Prototype `todoTag`, `filterTag`, `query`, `searchOpen`, `tagMenuOpen`, `filterMenuOpen`.
    /// Tag picked in the quick-add row; nil = none (the todo has no tag).
    private(set) var todoTag: String?
    private(set) var filterTag = "all"
    var query = ""
    private(set) var searchOpen = false
    private(set) var tagMenuOpen = false
    private(set) var filterMenuOpen = false
    /// Tags created with `New tag`, in creation order; saved with the todos.
    private(set) var customTags: [CustomTag]
    /// The name + colour popup over a tag menu: `newTag` is its name field, `tagHex` the picked swatch, `editingTag`
    /// the tag being edited (nil = adding). Never saved.
    private(set) var tagFormOpen = false
    /// The `Manage tags` list (every tag with edit / delete) in place of the picker list; never saved.
    private(set) var tagManageOpen = false
    private(set) var editingTag: String?
    var newTag = ""
    var tagHex = NotesStore.tagPalette[0]
    /// Todo being edited inline, and its title field; never saved.
    private(set) var editId: Int?
    var editDraft = ""
    /// Tag picked for the todo being edited ("" = none), and its tag menu; never saved.
    private(set) var editTag = ""
    private(set) var editTagMenuOpen = false
    /// Last deleted todo and where it was, for Undo. Cleared by the next add or undo.
    private(set) var deleted: (todo: TodoSample, index: Int)?

    // Copy & Double-click state, never saved.
    private(set) var copiedId: Int?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored var copyToClipboard: (String) -> Void = Clipboard.copy
    @ObservationIgnored var onCopied: () -> Void = {}
    @ObservationIgnored var doubleClickInterval: TimeInterval = NSEvent.doubleClickInterval
    @ObservationIgnored var pause: (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    private(set) var hintShown = false
    @ObservationIgnored private var tapTask: Task<Void, Never>?
    @ObservationIgnored private var tapId: Int?
    static let hintTime: TimeInterval = 1.6

    /// New tags take these colours in turn (Prototype `palette`).
    static let tagPalette: [UInt32] = [0xFFD86B, 0x7CE38B, 0xFFB38A, 0x8AB4FF, 0xFF8AD8, 0xB4F0FF]

    @ObservationIgnored private let url: URL?
    @ObservationIgnored var now: () -> Date = Date.init

    nonisolated static var defaultURL: URL { JSONFile.url("notes.json") }

    /// v1 files also hold the deleted Tagged notes (`notes`); decoding ignores that key and the next save drops it.
    private struct Snapshot: Codable {
        var todos: [TodoSample]
        /// Absent in files written before custom tags existed.
        var customTags: [CustomTag]?
    }

    /// Reads `url` if it exists, otherwise starts from `seed` (empty unless a snapshot or test passes one).
    init(url: URL? = NotesStore.defaultURL, seed: [TodoSample] = []) {
        self.url = url
        let saved = JSONFile.load(Snapshot.self, from: url)
        todos = saved?.todos ?? seed
        customTags = saved?.customTags ?? []
    }

    /// Fixed sample content, nothing read or written: what the snapshots draw.
    static func sample() -> NotesStore { NotesStore(url: nil, seed: SampleData.todos) }

    // MARK: Derived

    var doneCount: Int { todos.filter(\.done).count }
    var leftCount: Int { todos.count - doneCount }

    /// Hover: how many todos are left and done; nil when there are none at all.
    var peekTodo: PeekTodo? { todos.isEmpty ? nil : PeekTodo(left: leftCount, done: doneCount) }

    /// Query as matched: trimmed and lower-cased.
    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var isFiltered: Bool { filterTag != "all" || !needle.isEmpty }

    /// Todos the filter and the search let through; the title or the tag must contain the query.
    var visibleTodos: [TodoSample] {
        todos.filter { t in
            (filterTag == "all" || t.tag == filterTag)
                && (needle.isEmpty || t.title.lowercased().contains(needle) || t.tag.contains(needle))
        }
    }

    /// `visibleTodos` grouped by the day they were added, newest day first; todos without a date go last under "Earlier".
    var sections: [TodoSection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now())
        func title(_ day: Date) -> String {
            switch cal.dateComponents([.day], from: day, to: today).day {
            case 0: "Today"
            case 1: "Yesterday"
            default: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }
        }
        let todos = visibleTodos
        let days = Set(todos.compactMap { $0.createdAt.map(cal.startOfDay) }).sorted(by: >)
        var out = days.map { day in
            TodoSection(title: title(day), todos: todos.filter { $0.createdAt.map(cal.startOfDay) == day })
        }
        let undated = todos.filter { $0.createdAt == nil }
        if !undated.isEmpty { out.append(TodoSection(title: "Earlier", todos: undated)) }
        return out
    }

    /// The user's tags, then any other tag a todo carries (Prototype `tagOrder`).
    var tagOrder: [String] {
        var order: [String] = []
        for tag in customTags.map(\.id) + todos.map(\.tag) where !tag.isEmpty && !order.contains(tag) { order.append(tag) }
        return order
    }

    /// Colour of a tag the user created; nil for every other tag.
    func customColor(_ tag: String) -> Color? {
        customTags.first { $0.id == tag }.map { Color(hex: $0.hex) }
    }

    /// `New tag` input as a tag name (Prototype `cleanTag`): no leading `#`, lower case, other characters become `-`, max 20.
    static func cleanTag(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.lowercased().replacing(/[^a-z0-9_-]+/, with: "-").replacing(/^-+|-+$/, with: "")
        return String(s.prefix(20))
    }

    var canAddNewTag: Bool { !Self.cleanTag(newTag).isEmpty }

    func count(of tag: String) -> Int { todos.filter { $0.tag == tag }.count }

    /// Search field counter: empty until something is typed.
    var foundText: String { needle.isEmpty ? "" : "\(visibleTodos.count) found" }

    /// `No todos match <this>.` (Prototype `emptyWhat`).
    var emptyWhat: String {
        let parts = [filterTag == "all" ? nil : "#\(filterTag)",
                     needle.isEmpty ? nil : "“\(query.trimmingCharacters(in: .whitespacesAndNewlines))”"]
        return parts.compactMap { $0 }.joined(separator: " + ").nonEmpty ?? "this view"
    }

    var footer: String {
        if deleted != nil { return "Todo deleted" }
        if copiedId != nil { return "Copied to clipboard" }
        return isFiltered ? "\(visibleTodos.count) of \(todos.count) shown · \(leftCount) left" : "\(leftCount) left · \(doneCount) done"
    }

    // MARK: Actions

    /// Quick-add (Prototype `addTodo`): the first `#tag` in the text wins, else the picked tag, else none; every `#tag` is dropped from the title.
    func addTodo() {
        guard add(draft, tag: todoTag) != nil else { return }
        draft = ""
        tagMenuOpen = false
    }

    /// Adds `text` as a new todo on top; quick-add and Claude Code (`mwd-mcp`) both come through here. The first `#tag`
    /// in the text wins over `tag` (already clean: `cleanTag` isn't idempotent at its length cap). Nil when the text is blank.
    @discardableResult
    func add(_ text: String, tag: String?) -> TodoSample? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let tagged = /#([A-Za-z0-9_-]+)/
        let tag = raw.firstMatch(of: tagged).map { String($0.1).lowercased() } ?? tag ?? ""
        let stripped = raw.replacing(tagged, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = (todos.map(\.id).max() ?? 0) + 1
        let todo = TodoSample(id: id, title: stripped.isEmpty ? raw : stripped, tag: tag, due: "Today", createdAt: now())
        todos.insert(todo, at: 0)
        deleted = nil
        save()
        return todo
    }

    func toggleTagMenu() {
        tagMenuOpen.toggle()
        filterMenuOpen = false
        editTagMenuOpen = false
        tagManageOpen = false
        dropTagForm()
    }

    func toggleFilterMenu() {
        filterMenuOpen.toggle()
        tagMenuOpen = false
        editTagMenuOpen = false
        tagManageOpen = false
        dropTagForm()
    }

    /// Tag button of the todo being edited.
    func toggleEditTagMenu() {
        editTagMenuOpen.toggle()
        tagMenuOpen = false
        filterMenuOpen = false
        tagManageOpen = false
        dropTagForm()
    }

    /// Outside click: the tag menus, the manage list and the name + colour popup.
    func closeMenus() {
        tagMenuOpen = false
        filterMenuOpen = false
        editTagMenuOpen = false
        tagManageOpen = false
        dropTagForm()
    }

    /// `Manage tags` row of either menu / the manage list's `Done`.
    func openTagManage() { tagManageOpen = true }
    func closeTagManage() { tagManageOpen = false }

    private func dropTagForm() {
        tagFormOpen = false
        editingTag = nil
        newTag = ""
    }

    /// `New tag` button (`editing == nil`) or a row's pencil: opens the name + colour popup, pre-filled when editing.
    func openTagForm(editing tag: String? = nil) {
        editingTag = tag
        newTag = tag ?? ""
        tagHex = tag.flatMap { t in customTags.first { $0.id == t }?.hex } ?? Self.tagPalette[customTags.count % Self.tagPalette.count]
        tagFormOpen = true
    }

    /// Back to the menu list.
    func cancelTagForm() { dropTagForm() }

    /// Add: creates the tag (unless the name exists), picks it when opened from the assign menu, stays in the filter menu.
    /// Edit: renames the tag on every todo (an existing name merges the two) and recolours it. Blank name cancels, like the todo editor.
    func saveTagForm() {
        defer { dropTagForm() }
        let id = Self.cleanTag(newTag)
        guard !id.isEmpty else { return }
        if let old = editingTag {
            let merges = id != old && tagOrder.contains(id)
            if id != old {
                for i in todos.indices where todos[i].tag == old { todos[i].tag = id }
                if filterTag == old { filterTag = id }
                if todoTag == old { todoTag = id }
                if editTag == old { editTag = id }
            }
            if let i = customTags.firstIndex(where: { $0.id == old }) {
                if merges { customTags.remove(at: i) } else { customTags[i] = CustomTag(id: id, hex: tagHex) }
            } else if !merges {
                customTags.append(CustomTag(id: id, hex: tagHex)) // tag that only lived on todos
            }
            save()
        } else {
            if !tagOrder.contains(id) {
                customTags.append(CustomTag(id: id, hex: tagHex))
                save()
            }
            if tagMenuOpen, !tagManageOpen { pickTodoTag(id) }
            if editTagMenuOpen, !tagManageOpen { pickEditTag(id) }
        }
    }

    /// Removes the tag; its todos keep no tag.
    func deleteTag(_ tag: String) {
        for i in todos.indices where todos[i].tag == tag { todos[i].tag = "" }
        customTags.removeAll { $0.id == tag }
        if filterTag == tag { filterTag = "all" }
        if todoTag == tag { todoTag = nil }
        if editTag == tag { editTag = "" }
        save()
    }

    func pickTodoTag(_ tag: String?) {
        todoTag = tag
        tagMenuOpen = false
    }

    func pickEditTag(_ tag: String?) {
        editTag = tag ?? ""
        editTagMenuOpen = false
    }

    func pickFilter(_ tag: String) {
        filterTag = tag
        filterMenuOpen = false
    }

    func openSearch() { searchOpen = true }

    func closeSearch() {
        searchOpen = false
        query = ""
    }

    /// Empty state's button.
    func clearFilters() {
        filterTag = "all"
        closeSearch()
    }

    /// Sub-tab switch: drops the query, the search field and any open menu (the picked tag and filter stay).
    func resetTransient() {
        endEdit()
        deleted = nil
        copiedId = nil
        tapTask?.cancel()
        tapTask = nil
        tapId = nil
        hintShown = false
        closeSearch()
        closeMenus()
    }

    func copy(_ id: Int) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        copyToClipboard(todo.title)
        copiedId = id
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.copiedId = nil
        }
        onCopied()
    }

    /// Click on a todo row. A second click within the double-click interval copies it; if none comes, the hint toast
    /// about the double-click shows. Returns the running sequence so tests can wait for it.
    @discardableResult
    func tap(_ id: Int) -> Task<Void, Never>? {
        tapTask?.cancel()
        tapTask = nil
        if tapId == id {
            tapId = nil
            hintShown = false
            copy(id)
            return nil
        }
        tapId = id
        let run = Task { [weak self] in
            guard let self else { return }
            await pause(doubleClickInterval)
            guard !Task.isCancelled else { return }
            tapId = nil
            hintShown = true
            await pause(Self.hintTime)
            guard !Task.isCancelled else { return }
            hintShown = false
        }
        tapTask = run
        return run
    }

    func showCopied(_ id: Int) {
        copiedId = id
    }

    func toggle(_ id: Int) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        save()
    }

    func startEdit(_ id: Int) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        editId = id
        editDraft = todo.title
        editTag = todo.tag
        editTagMenuOpen = false
    }

    /// Empty text cancels, like Commands and Prompts. Changes the title and the tag.
    func saveEdit() {
        let title = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, let i = todos.firstIndex(where: { $0.id == editId }) {
            todos[i].title = title
            todos[i].tag = editTag
            save()
        }
        endEdit()
    }

    func cancelEdit() { endEdit() }

    private func endEdit() {
        editId = nil
        editTagMenuOpen = false
    }

    func delete(_ id: Int) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if copiedId == id { copiedId = nil }
        deleted = (todos.remove(at: i), i)
        endEdit()
        save()
    }

    func undo() {
        guard let d = deleted else { return }
        todos.insert(d.todo, at: min(d.index, todos.count))
        deleted = nil
        save()
    }

    private func save() { saveError = JSONFile.save(Snapshot(todos: todos, customTags: customTags), to: url) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
