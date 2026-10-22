import Foundation
import Lottie

/// The custom buddies the user has added: Lottie files kept in one folder, each one checked (`BuddyFileCheck`) before it was written
/// there. The folder is what lasts between launches, so there is no index to fall out of step with it; a file in it that fails the check
/// today (hand-edited, or a stricter app) is left alone and simply not offered.
@MainActor @Observable
final class CustomBuddyStore {
    struct Entry: Identifiable, Equatable {
        /// The file name without `.json`. This is what Settings remembers.
        let id: String
        let url: URL
    }

    /// Oldest first, so a new one lands next to the + tile.
    private(set) var entries: [Entry]
    /// Why the last file was turned down; empty after one is taken.
    private(set) var rejection: [String] = []
    /// nil: nothing is read or saved (snapshots, tests).
    private let folder: URL?

    init(folder: URL?, entries: [Entry] = [], rejection: [String] = []) {
        self.folder = folder
        self.entries = entries
        self.rejection = rejection
        guard let folder else { return }
        let keys: [URLResourceKey] = [.creationDateKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let (da, db) = (a.creationDate, b.creationDate)
                return da == db ? a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending : da < db
            }
        self.entries = files.compactMap { url in
            guard let data = try? Data(contentsOf: url), BuddyFileCheck.check(data).accepted else {
                NSLog("MyWorkDock: custom buddy %@ no longer passes the check, left out", url.lastPathComponent)
                return nil
            }
            return Entry(id: url.deletingPathExtension().lastPathComponent, url: url)
        }
    }

    static func live() -> CustomBuddyStore { CustomBuddyStore(folder: .applicationSupportDirectory.appending(path: "MyWorkDock/Buddies")) }
    static func sample(_ entries: [Entry] = [], rejection: [String] = []) -> CustomBuddyStore { CustomBuddyStore(folder: nil, entries: entries, rejection: rejection) }

    func entry(_ id: String?) -> Entry? { entries.first { $0.id == id } }

    /// Checks the file and, if it passes, keeps exactly the bytes that were checked (so the original can move or change). Returns the
    /// new buddy's id; nil with `rejection` set when it is turned down.
    @discardableResult
    func add(from source: URL) -> String? {
        guard let folder else { return nil }
        guard entries.count < BuddyFileCheck.Limits.library else {
            return refuse("The library is full (\(BuddyFileCheck.Limits.library) buddies). Remove one first.")
        }
        guard let data = try? Data(contentsOf: source) else { return refuse("Could not read the file.") }
        let verdict = BuddyFileCheck.check(data)
        guard verdict.accepted else {
            rejection = verdict.reasons
            return nil
        }
        let id = freeName(for: source.deletingPathExtension().lastPathComponent)
        let url = folder.appending(path: "\(id).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return refuse("Could not save it: \(error.localizedDescription)")
        }
        rejection = []
        entries.append(Entry(id: id, url: url))
        LottieAnimationCache.shared?.clearCache() // it keeps animations by path
        return id
    }

    func remove(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        if folder != nil { try? FileManager.default.removeItem(at: entry.url) }
        entries.removeAll { $0.id == id }
        rejection = []
        LottieAnimationCache.shared?.clearCache()
    }

    private func refuse(_ reason: String) -> String? {
        rejection = [reason]
        return nil
    }

    // MARK: Names

    /// The file's own name, kept to letters, digits, spaces, `-` and `_` (it becomes a file name here), numbered when it is taken.
    private func freeName(for stem: String) -> String {
        let kept = String(stem.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0) ? Character($0) : "-" })
        let trimmed = String(kept.trimmingCharacters(in: CharacterSet(charactersIn: " -")).prefix(40))
        let name = trimmed.isEmpty ? "Buddy" : trimmed
        let taken = Set(entries.map { $0.id.lowercased() }) // the file system may not tell Cat from cat
        guard taken.contains(name.lowercased()) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)".lowercased()) { n += 1 }
        return "\(name) \(n)"
    }
}

private extension URL {
    var creationDate: Date { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast }
}
