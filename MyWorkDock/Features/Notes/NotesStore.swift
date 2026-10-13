import SwiftUI
import Observation

/// A tag created with `New tag`: name and the colour it was given.
struct CustomTag: Codable, Equatable {
    var id: String
    var hex: UInt32
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
    /// Tag picked in the quick-add row; nil = none (the todo falls back to `misc`).
    private(set) var todoTag: String?
    private(set) var filterTag = "all"
    var query = ""
    private(set) var searchOpen = false
    private(set) var tagMenuOpen = false
    private(set) var filterMenuOpen = false
    /// Text of the `New tag` field in the tag menu.
    var newTag = ""
    /// Tags created with `New tag`, in creation order; saved with the todos.
    private(set) var customTags: [CustomTag]

    /// Tags every menu lists first; tags that only live on todos are appended (Prototype `tagOrder`).
    static let baseTags = ["release", "bug", "deps", "docs"]
    /// New tags take these colours in turn (Prototype `palette`).
    static let tagPalette: [UInt32] = [0xFFD86B, 0x7CE38B, 0xFFB38A, 0x8AB4FF, 0xFF8AD8, 0xB4F0FF]

    @ObservationIgnored private let url: URL?

    nonisolated static var defaultURL: URL { JSONFile.url("notes.json") }

    /// v1 files also hold the deleted Tagged notes (`notes`); decoding ignores that key and the next save drops it.
    private struct Snapshot: Codable {
        var todos: [TodoSample]
        /// Absent in files written before custom tags existed.
        var customTags: [CustomTag]?
    }

    /// Reads `url` if it exists, otherwise starts from `seed` (the designs' sample content).
    init(url: URL? = NotesStore.defaultURL, seed: [TodoSample] = SampleData.todos) {
        self.url = url
        let saved = JSONFile.load(Snapshot.self, from: url)
        todos = saved?.todos ?? seed
        customTags = saved?.customTags ?? []
    }

    /// Fixed sample content, nothing read or written: what the snapshots draw.
    static func sample() -> NotesStore { NotesStore(url: nil) }

    // MARK: Derived

    var doneCount: Int { todos.filter(\.done).count }
    var leftCount: Int { todos.count - doneCount }

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

    /// Base tags, then the user's, then any other tag a todo carries (Prototype `tagOrder`).
    var tagOrder: [String] {
        var order = Self.baseTags
        for tag in customTags.map(\.id) + todos.map(\.tag) where !order.contains(tag) { order.append(tag) }
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
        isFiltered ? "\(visibleTodos.count) of \(todos.count) shown · \(leftCount) left" : "\(leftCount) left · \(doneCount) done"
    }

    // MARK: Actions

    /// Quick-add (Prototype `addTodo`): the first `#tag` in the text wins, else the picked tag, else `misc`; every `#tag` is dropped from the title.
    func addTodo() {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let tagged = /#([A-Za-z0-9_-]+)/
        let tag = raw.firstMatch(of: tagged)?.1.lowercased() ?? todoTag ?? "misc"
        let stripped = raw.replacing(tagged, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = (todos.map(\.id).max() ?? 0) + 1
        todos.insert(TodoSample(id: id, title: stripped.isEmpty ? raw : stripped, tag: tag, due: "Today"), at: 0)
        draft = ""
        tagMenuOpen = false
        save()
    }

    func toggleTagMenu() {
        tagMenuOpen.toggle()
        filterMenuOpen = false
    }

    func toggleFilterMenu() {
        filterMenuOpen.toggle()
        tagMenuOpen = false
    }

    /// `New tag` field: creates the tag (unless it exists), picks it for the next todo and closes the menu.
    func addNewTag() {
        let id = Self.cleanTag(newTag)
        guard !id.isEmpty else { return }
        if !Self.baseTags.contains(id), !customTags.contains(where: { $0.id == id }) {
            customTags.append(CustomTag(id: id, hex: Self.tagPalette[customTags.count % Self.tagPalette.count]))
            save()
        }
        newTag = ""
        pickTodoTag(id)
    }

    /// Esc in the `New tag` field.
    func cancelNewTag() {
        newTag = ""
        tagMenuOpen = false
    }

    func pickTodoTag(_ tag: String?) {
        todoTag = tag
        tagMenuOpen = false
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
        closeSearch()
        tagMenuOpen = false
        filterMenuOpen = false
    }

    func toggle(_ id: Int) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].done.toggle()
        save()
    }

    private func save() { saveError = JSONFile.save(Snapshot(todos: todos, customTags: customTags), to: url) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
