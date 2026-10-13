import Foundation
import Observation

/// The two lists that share one store and one view: Notes › Commands and Notes › Prompts.
enum SnippetKind {
    case commands, prompts

    var noun: String { self == .commands ? "command" : "prompt" }
    var glyph: String { self == .commands ? "$" : "✦" }
    /// `commands.json` is the v1 file name, kept so saved commands survive the upgrade.
    var file: String { self == .commands ? "commands.json" : "prompts.json" }
    var placeholder: String { self == .commands ? "Paste or type a command, press Enter" : "Paste or write a prompt, press Enter" }
    var seed: [String] { self == .commands ? SampleData.commands : SampleData.prompts }
}

struct SnippetItem: Identifiable, Codable, Equatable {
    var id: Int
    var text: String
}

/// Saved commands or prompts: add, inline edit, copy, delete with one-step undo (Prototype `cmds` / `prompts`).
@MainActor @Observable
final class SnippetStore {
    let kind: SnippetKind
    private(set) var items: [SnippetItem]
    /// Add-field text; cleared on sub-tab switch like the prototype, never saved.
    var draft = ""
    private(set) var editId: Int?
    /// Why the last save failed; shown in the footer.
    private(set) var saveError: String?
    var editDraft = ""
    private(set) var copiedId: Int?
    /// Last deleted item and where it was, for Undo. Cleared by the next add or undo.
    private(set) var deleted: (item: SnippetItem, index: Int)?
    /// Sub-nav search (Prompts only in the UI); never saved.
    var query = ""
    private(set) var searchOpen = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored var copyToClipboard: (String) -> Void = Clipboard.copy
    @ObservationIgnored private var copyTask: Task<Void, Never>?

    /// `url == nil` keeps everything in memory (snapshots, tests). Reads `url` if it exists, otherwise starts from `seed`.
    init(_ kind: SnippetKind, url: URL?, seed: [String]) {
        self.kind = kind
        self.url = url
        items = JSONFile.load([SnippetItem].self, from: url)
            ?? seed.enumerated().map { SnippetItem(id: $0.offset + 1, text: $0.element) }
    }

    static func persistent(_ kind: SnippetKind) -> SnippetStore { SnippetStore(kind, url: JSONFile.url(kind.file), seed: kind.seed) }
    static func sample(_ kind: SnippetKind) -> SnippetStore { SnippetStore(kind, url: nil, seed: kind.seed) }

    /// Query as matched: trimmed and lower-cased.
    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var isSearching: Bool { !needle.isEmpty }

    /// Items whose text contains the query; everything while the query is empty. Order is the list's.
    var visibleItems: [SnippetItem] {
        isSearching ? items.filter { $0.text.lowercased().contains(needle) } : items
    }

    /// Search field counter: empty until something is typed.
    var foundText: String { isSearching ? "\(visibleItems.count) found" : "" }

    /// `No prompts match “q”.`
    var emptyText: String { "No \(kind.noun)s match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”." }

    var footer: String {
        if deleted != nil { return "\(kind.noun.capitalized) deleted" }
        if copiedId != nil { return "Copied to clipboard" }
        return isSearching ? "\(visibleItems.count) of \(items.count) \(kind.noun)s shown" : "\(items.count) saved \(kind.noun)s"
    }

    func openSearch() { searchOpen = true }

    func closeSearch() {
        searchOpen = false
        query = ""
    }

    func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items.insert(SnippetItem(id: (items.map(\.id).max() ?? 0) + 1, text: text), at: 0)
        draft = ""
        deleted = nil
        save()
    }

    func startEdit(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        editId = id
        editDraft = item.text
    }

    /// Empty text cancels, like the prototype.
    func saveEdit() {
        let text = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let i = items.firstIndex(where: { $0.id == editId }) {
            items[i].text = text
            save()
        }
        editId = nil
    }

    func cancelEdit() { editId = nil }

    /// Sub-tab switch (Prototype `sub.pick`): drops the edit, the draft, the undo, the "Copied" state and the search.
    func reset() {
        editId = nil
        draft = ""
        deleted = nil
        copiedId = nil
        closeSearch()
    }

    func copy(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        copyToClipboard(item.text)
        copiedId = id
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.copiedId = nil
        }
    }

    func delete(_ id: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        deleted = (items.remove(at: i), i)
        editId = nil
        save()
    }

    func undo() {
        guard let d = deleted else { return }
        items.insert(d.item, at: min(d.index, items.count))
        deleted = nil
        save()
    }

    /// Snapshot states only.
    func showCopied(_ id: Int) { copiedId = id }

    private func save() { saveError = JSONFile.save(items, to: url) }
}
