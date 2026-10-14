import AppKit
import Foundation
import Observation

/// The lists that share one store and one view: Notes › Commands, Notes › Prompts and Notes › Links.
enum SnippetKind {
    case commands, prompts, links

    var noun: String {
        switch self {
        case .commands: "command"
        case .prompts: "prompt"
        case .links: "link"
        }
    }

    var glyph: String {
        switch self {
        case .commands: "$"
        case .prompts: "✦"
        case .links: "↗"
        }
    }

    /// `commands.json` is the v1 file name, kept so saved commands survive the upgrade.
    var file: String {
        switch self {
        case .commands: "commands.json"
        case .prompts: "prompts.json"
        case .links: "links.json"
        }
    }

    var placeholder: String {
        switch self {
        case .commands: "Paste or type a command, press Enter"
        case .prompts: "Paste or write a prompt, press Enter"
        case .links: "Paste a link, press Enter"
        }
    }

    /// Sample content for snapshots and tests only; the real lists start empty.
    var seed: [String] {
        switch self {
        case .commands: SampleData.commands
        case .prompts: SampleData.prompts
        case .links: SampleData.links
        }
    }

    /// Shown instead of the list when nothing is saved.
    var emptyTitle: String { "No \(noun)s saved yet" }

    var emptyHint: String {
        switch self {
        case .commands: "Type or paste a command above, then press Enter."
        case .prompts: "Write a prompt above, then press Enter."
        case .links: "Paste a link above, then press Enter."
        }
    }
}

struct SnippetItem: Identifiable, Codable, Equatable {
    var id: Int
    var text: String
}

/// Saved commands, prompts or links: add, inline edit, copy, delete with one-step undo (Prototype `cmds` / `prompts`).
/// Links also open in the default browser.
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
    /// Toast telling the user an item is copied with a double-click.
    private(set) var hintShown = false
    /// Last deleted item and where it was, for Undo. Cleared by the next add or undo.
    private(set) var deleted: (item: SnippetItem, index: Int)?
    /// Sub-nav search (Prompts and Links in the UI); never saved.
    var query = ""
    private(set) var searchOpen = false

    @ObservationIgnored private let url: URL?
    @ObservationIgnored var copyToClipboard: (String) -> Void = Clipboard.copy
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    /// Row clicked once and still waiting for its second click.
    @ObservationIgnored private var tapId: Int?
    @ObservationIgnored private var tapTask: Task<Void, Never>?
    @ObservationIgnored var doubleClickInterval = NSEvent.doubleClickInterval
    static let hintTime: TimeInterval = 1.8
    /// Waits `seconds`; tests replace it so the sequence finishes at once.
    @ObservationIgnored var pause: (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }

    /// `url == nil` keeps everything in memory (snapshots, tests). Reads `url` if it exists, otherwise starts from `seed`.
    init(_ kind: SnippetKind, url: URL?, seed: [String]) {
        self.kind = kind
        self.url = url
        items = JSONFile.load([SnippetItem].self, from: url)
            ?? seed.enumerated().map { SnippetItem(id: $0.offset + 1, text: $0.element) }
    }

    static func persistent(_ kind: SnippetKind) -> SnippetStore { SnippetStore(kind, url: JSONFile.url(kind.file), seed: []) }
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

    /// Trimmed text. A link is one line with no spaces, so a multi-line paste is joined up.
    private func clean(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return kind == .links ? text.components(separatedBy: .whitespacesAndNewlines).joined() : text
    }

    func add() {
        let text = clean(draft)
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
        let text = clean(editDraft)
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
        tapTask?.cancel()
        tapTask = nil
        tapId = nil
        hintShown = false
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

    /// Click on an item's text. A second click within the double-click interval copies it; if none comes, the hint toast
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

    /// A saved link as a URL: text with a scheme is used as written, anything else gets `https://`. nil when it is not a URL.
    static func url(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return URL(string: text.contains("://") ? text : "https://" + text)
    }

    /// Opens a saved link in the default browser; text that is not a URL does nothing.
    func open(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }), let url = Self.url(from: item.text) else { return }
        openURL(url)
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
