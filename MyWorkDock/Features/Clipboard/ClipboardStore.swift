import SwiftUI
import Observation

struct ClipItem: Codable, Identifiable, Equatable {
    var id: Int
    var text: String
    var pinned = false
    /// One tag per clip, stored without the `#`. History saved before tags existed has none.
    var tag: String?
}

/// What clipboard.json holds. Files from before tag colours are a bare array of clips.
private struct Saved: Codable {
    var items: [ClipItem]
    var customTags: [CustomTag]?
    /// How many untagged clips to keep; absent in older files.
    var limit: Int?
}

/// Clipboard history: text only, newest first, pinned clips never fall off the end.
/// macOS has no "pasteboard changed" push, so a 0.5 s timer compares `changeCount` (reading the content is what
/// can raise the "Paste from Other Apps" prompt, so it only happens after a change).
@MainActor @Observable
final class ClipboardStore {
    /// Settings › Clipboard: how many untagged clips are kept, 1…`maxLimit`. Tagged and pinned clips are not counted and never dropped.
    static let defaultLimit = 200
    static let maxLimit = 1000
    /// Clips longer than this are ignored (the history is a JSON file rewritten on every copy).
    static let maxChars = 50_000
    /// Password managers: whatever is copied while one is frontmost is never recorded.
    static let defaultExcluded: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.Passwords", "com.apple.keychainaccess", "org.keepassxc.keepassxc",
    ]

    private(set) var items: [ClipItem]
    /// Hover: how many clips are saved and how many of them are pinned; nil when the history is empty.
    var peekClips: PeekClips? { items.isEmpty ? nil : PeekClips(total: items.count, pinned: items.filter(\.pinned).count) }
    private(set) var limit: Int
    private(set) var copiedId: Int?
    /// Toast telling the user a clip is copied with a double-click.
    private(set) var hintShown = false
    private(set) var saveError: String?
    /// Search text; never saved.
    var query = ""
    private(set) var searchOpen = false
    /// Tag chip selected above the list; nil = all clips. Never saved.
    private(set) var filterTag: String?
    /// Tags created with `New tag`, in creation order, each with its colour; saved with the clips. Every tag a clip carries is here.
    private(set) var customTags: [CustomTag]
    /// Clip whose assign-tag menu is open.
    private(set) var tagPickerId: Int?
    /// The `Manage tags` list and the name + colour popup, as in Notes › TODO: `newTag` is the popup's name field, `tagHex`
    /// the picked swatch, `editingTag` the tag being edited (nil = adding). Never saved.
    private(set) var tagManageOpen = false
    private(set) var tagFormOpen = false
    private(set) var editingTag: String?
    var newTag = ""
    var tagHex = NotesStore.tagPalette[0]

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let excluded: Set<String>
    @ObservationIgnored var changeCount: () -> Int
    /// Plain text on the pasteboard; nil when there is none or the source marked it secret.
    @ObservationIgnored var readText: () -> String?
    /// Bundle ID of the frontmost app: the panel never activates, so while the user copies this is the source app.
    @ObservationIgnored var frontApp: () -> String?
    /// True once the user switched MyWorkDock to "Don't allow" under Paste from Other Apps.
    @ObservationIgnored var accessDenied: () -> Bool = { false }
    @ObservationIgnored var copyToClipboard: (String) -> Void = Clipboard.copy
    /// Called after an item is copied; the shell closes the panel.
    @ObservationIgnored var onCopied: () -> Void = {}
    @ObservationIgnored let confirmer: Confirmer
    @ObservationIgnored private var lastCount = -1
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    /// Row clicked once and still waiting for its second click.
    @ObservationIgnored private var tapId: Int?
    @ObservationIgnored private var tapTask: Task<Void, Never>?
    @ObservationIgnored var doubleClickInterval = NSEvent.doubleClickInterval
    static let hintTime: TimeInterval = 1.8
    /// Waits `seconds`; tests replace it so the sequence finishes at once.
    @ObservationIgnored var pause: (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    /// Only the running app polls; sample and test stores never start a timer.
    @ObservationIgnored private var polls = false

    init(url: URL?, seed: [ClipItem] = [], excluded: Set<String> = [],
         changeCount: @escaping () -> Int = { 0 }, readText: @escaping () -> String? = { nil },
         frontApp: @escaping () -> String? = { nil },
         confirmer: Confirmer? = nil) {
        self.url = url
        self.excluded = excluded
        self.changeCount = changeCount
        self.readText = readText
        self.frontApp = frontApp
        self.confirmer = confirmer ?? Confirmer()
        let saved = JSONFile.load(Saved.self, from: url) ?? JSONFile.load([ClipItem].self, from: url).map { Saved(items: $0) }
        let loaded = saved?.items ?? seed
        var known = saved?.customTags ?? []
        // A tag with no colour yet (clips tagged before colours existed) takes the next palette colour.
        for tag in Set(loaded.compactMap(\.tag)).subtracting(known.map(\.id)).sorted() {
            known.append(CustomTag(id: tag, hex: NotesStore.tagPalette[known.count % NotesStore.tagPalette.count]))
        }
        items = loaded
        customTags = known
        limit = Self.clamp(saved?.limit ?? Self.defaultLimit)
    }

    /// The running app. Extra bundle IDs to skip go in the `clipboardExcludedApps` default (no UI yet).
    static func live(confirmer: Confirmer? = nil) -> ClipboardStore {
        let extra = Set(UserDefaults.standard.stringArray(forKey: "clipboardExcludedApps") ?? [])
        let store = ClipboardStore(url: JSONFile.url("clipboard.json"), excluded: defaultExcluded.union(extra),
                                   changeCount: { NSPasteboard.general.changeCount },
                                   readText: SystemPasteboard.text,
                                   frontApp: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
                                   confirmer: confirmer)
        store.accessDenied = SystemPasteboard.accessDenied
        store.polls = true
        return store
    }

    static func sample(confirmer: Confirmer? = nil) -> ClipboardStore {
        ClipboardStore(url: nil, seed: [
            ClipItem(id: 1, text: "npm run build -- --watch", tag: "dev"),
            ClipItem(id: 2, text: "https://developer.apple.com/documentation/appkit/nspasteboard", pinned: true, tag: "docs"),
            ClipItem(id: 3, text: "git commit -m \"feat: add clipboard tab\"\ngit push -u origin HEAD:refs/heads/feat/clipboard-tab\n# then open the pull request\n# this fourth line is cut off", tag: "dev"),
            ClipItem(id: 4, text: "feat: add clipboard tab", tag: "git"),
        ], confirmer: confirmer)
    }

    // MARK: Polling

    func startMonitoring() {
        guard polls, timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common) // .common: keeps ticking while a menu or scroll tracks
        self.timer = timer
    }

    /// Clipboard menu switched off: nothing is read or recorded any more.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func poll() {
        let count = changeCount()
        guard count != lastCount else { return }
        lastCount = count
        guard !excluded.contains(frontApp() ?? ""), let text = readText() else { return }
        record(text)
    }

    private func record(_ text: String) {
        let key = Self.key(text)
        guard !key.isEmpty, text.count <= Self.maxChars else { return }
        var item = ClipItem(id: (items.map(\.id).max() ?? 0) + 1, text: text)
        // Same clip again (a trailing newline or space doesn't make it a new one): no second entry, it goes back to the top.
        if let i = items.firstIndex(where: { Self.key($0.text) == key }) {
            item = items.remove(at: i)
            item.text = text
        }
        items.insert(item, at: 0)
        trim()
        save()
    }

    // MARK: Limit

    static func clamp(_ n: Int) -> Int { min(max(n, 1), maxLimit) }

    /// The limit only counts clips with no tag that are not pinned.
    private func isLimited(_ clip: ClipItem) -> Bool { !clip.pinned && clip.tag == nil }

    /// Oldest limited clips beyond the limit are dropped.
    private func trim() {
        var seen = 0
        items.removeAll { clip in
            guard isLimited(clip) else { return false }
            seen += 1
            return seen > limit
        }
    }

    /// How many clips lowering the limit to `n` would delete.
    func removalCount(at n: Int) -> Int { max(0, items.filter(isLimited).count - Self.clamp(n)) }

    /// Settings › Clipboard. Lowering it deletes the oldest limited clips at once (the caller confirms first).
    func setLimit(_ n: Int) {
        limit = Self.clamp(n)
        trim()
        save()
    }

    /// What makes two clips the same clip.
    private static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: List

    private var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var isSearching: Bool { !needle.isEmpty }

    var isFiltering: Bool { isSearching || filterTag != nil }

    /// Pinned clips first, then the rest newest first; narrowed by the tag chip and the search.
    var visibleItems: [ClipItem] {
        var found = items
        if let filterTag { found = found.filter { $0.tag == filterTag } }
        if isSearching { found = found.filter { $0.text.lowercased().contains(needle) } }
        return found.filter(\.pinned) + found.filter { !$0.pinned }
    }

    var foundText: String { isSearching ? "\(visibleItems.count) found" : "" }
    var emptyText: String {
        isSearching ? "No clips match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”." : "No clips tagged #\(filterTag ?? "")."
    }

    // MARK: Tags

    /// Every tag, in creation order.
    var tags: [String] { customTags.map(\.id) }

    func count(of tag: String) -> Int { items.filter { $0.tag == tag }.count }

    func customColor(_ tag: String) -> Color? {
        customTags.first { $0.id == tag }.map { Color(hex: $0.hex) }
    }

    var canAddNewTag: Bool { !NotesStore.cleanTag(newTag).isEmpty }

    /// Any of the tag menus (assign, manage, name + colour popup) is showing.
    var tagMenuOpen: Bool { tagPickerId != nil || tagManageOpen || tagFormOpen }

    /// A clip's tag button.
    func openTagPicker(_ id: Int) {
        closeMenus()
        tagPickerId = id
    }

    /// The chips row's `Manage`, or the assign menu's.
    func openTagManage() { tagManageOpen = true }
    func closeTagManage() { tagManageOpen = false }

    /// Outside click, tab switch, panel close.
    func closeMenus() {
        tagPickerId = nil
        tagManageOpen = false
        dropTagForm()
    }

    private func dropTagForm() {
        tagFormOpen = false
        editingTag = nil
        newTag = ""
    }

    /// `New tag` (`editing == nil`) or a manage-row pencil: opens the name + colour popup, pre-filled when editing.
    func openTagForm(editing tag: String? = nil) {
        editingTag = tag
        newTag = tag ?? ""
        tagHex = tag.flatMap { t in customTags.first { $0.id == t }?.hex } ?? NotesStore.tagPalette[customTags.count % NotesStore.tagPalette.count]
        tagFormOpen = true
    }

    func cancelTagForm() { dropTagForm() }

    /// Add: creates the tag (unless the name exists) and, when opened from a clip's assign menu, gives it to that clip.
    /// Edit: renames the tag on every clip (an existing name merges the two) and recolours it. A blank name cancels.
    func saveTagForm() {
        defer { dropTagForm() }
        let id = NotesStore.cleanTag(newTag)
        guard !id.isEmpty else { return }
        if let old = editingTag {
            let merges = id != old && tags.contains(id)
            if id != old {
                for i in items.indices where items[i].tag == old { items[i].tag = id }
                if filterTag == old { filterTag = id }
            }
            if let i = customTags.firstIndex(where: { $0.id == old }) {
                if merges { customTags.remove(at: i) } else { customTags[i] = CustomTag(id: id, hex: tagHex) }
            }
            save()
        } else {
            if !tags.contains(id) {
                customTags.append(CustomTag(id: id, hex: tagHex))
                save()
            }
            if let clip = tagPickerId, !tagManageOpen { assign(id, to: clip) }
        }
    }

    /// Removes the tag; its clips keep no tag.
    func deleteTag(_ tag: String) {
        for i in items.indices where items[i].tag == tag { items[i].tag = nil }
        customTags.removeAll { $0.id == tag }
        dropMissingFilter()
        save()
    }

    /// Sets or clears (nil) the clip's tag and closes the assign menu.
    func assign(_ tag: String?, to id: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].tag = tag
        closeMenus()
        save()
    }

    /// Chip tap: the tag again clears the filter, "All" (nil) always does.
    func pickFilter(_ tag: String?) { filterTag = filterTag == tag ? nil : tag }

    func clearFilters() {
        closeSearch()
        filterTag = nil
    }

    /// The filtered tag was deleted: back to all clips.
    private func dropMissingFilter() {
        if let filterTag, !tags.contains(filterTag) { self.filterTag = nil }
    }

    var footer: String {
        if accessDenied() { return "Allow MyWorkDock in Settings › Privacy › Paste from Other Apps" }
        if copiedId != nil { return "Copied to clipboard" }
        return isFiltering ? "\(visibleItems.count) of \(items.count) clips shown" : "\(items.count) clips · keeps the last \(limit) untagged · tagged and pinned stay"
    }

    func openSearch() { searchOpen = true }

    func closeSearch() {
        searchOpen = false
        query = ""
    }

    // MARK: Actions

    func copy(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        copyToClipboard(item.text)
        lastCount = changeCount() // our own write is not a new clip
        copiedId = id
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.copiedId = nil
        }
        onCopied()
    }

    /// Click on a clip's text. A second click within the double-click interval copies it; if none comes, the hint toast
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

    /// Snapshot states only.
    func showHint() { hintShown = true }

    func togglePin(_ id: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ id: Int) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Asks for confirmation via `confirmer`, then deletes clips if confirmed.
    func requestClearAll(preservePinned: Bool = true) {
        guard !items.isEmpty else { return }
        closeMenus()
        let unpinnedCount = items.filter { !$0.pinned }.count
        let pinnedCount = items.count - unpinnedCount

        let title: String
        let command: String
        let note: String
        let confirmTitle: String
        let includingPinned: Bool

        if preservePinned && pinnedCount > 0 {
            if unpinnedCount > 0 {
                title = "Clear clipboard history?"
                command = "Delete \(unpinnedCount) unpinned clip\(unpinnedCount == 1 ? "" : "s")"
                note = "\(pinnedCount) pinned clip\(pinnedCount == 1 ? "" : "s") will stay. This can't be undone."
                confirmTitle = "Clear \(unpinnedCount)"
                includingPinned = false
            } else {
                title = "Clear all pinned clips?"
                command = "Delete all \(pinnedCount) pinned clip\(pinnedCount == 1 ? "" : "s")"
                note = "This can't be undone."
                confirmTitle = "Clear all"
                includingPinned = true
            }
        } else {
            title = "Clear all clipboard history?"
            command = "Delete all \(items.count) clip\(items.count == 1 ? "" : "s")"
            note = "This can't be undone."
            confirmTitle = "Clear all"
            includingPinned = true
        }

        confirmer.ask(ConfirmRequest(title: title, command: command, note: note, confirmTitle: confirmTitle, danger: true) { [weak self] in
            self?.clearAll(includingPinned: includingPinned)
        })
    }

    func clearAll(includingPinned: Bool = true) {
        if includingPinned {
            items.removeAll()
        } else {
            items.removeAll { !$0.pinned }
        }
        copiedId = nil
        hintShown = false
        save()
    }

    private func save() { saveError = JSONFile.save(Saved(items: items, customTags: customTags, limit: limit), to: url) }
}

/// The real pasteboard. Reading content is the only call that can raise the system prompt.
enum SystemPasteboard {
    /// Types that password managers and "transient" sources add (nspasteboard.org): such a copy is never recorded.
    private static let secret: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
    ]

    static func text() -> String? {
        let pb = NSPasteboard.general
        guard !(pb.types ?? []).contains(where: { secret.contains($0.rawValue) }) else { return nil }
        return pb.string(forType: .string)
    }

    static func accessDenied() -> Bool {
        if #available(macOS 15.4, *) { return NSPasteboard.general.accessBehavior == .alwaysDeny }
        return false
    }
}
