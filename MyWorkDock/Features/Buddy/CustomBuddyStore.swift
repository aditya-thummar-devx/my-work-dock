import Foundation
import Lottie

/// The custom buddies the user has added. Each is a folder: `idle.json`, optionally `glance.json` and `nap.json` (BuddyState), and
/// `offsets.json`. Every Lottie file was checked (`BuddyFileCheck`) before it was written there. The folders are what lasts between
/// launches, so there is no index to fall out of step with them; a file that fails the check today (hand-edited, or a stricter app) is
/// left alone and simply not offered: without its idle file the buddy is left out, without a glance or nap file only that state is.
@MainActor @Observable
final class CustomBuddyStore {
    struct Entry: Identifiable, Equatable {
        /// The folder's name. This is what Settings remembers.
        let id: String
        /// The checked files, by state; idle is always there.
        var files: [BuddyState: URL]
        var offsets = BuddyOffsets()

        /// The idle file.
        var url: URL { files[.idle]! }

        init(id: String, files: [BuddyState: URL], offsets: BuddyOffsets = BuddyOffsets()) {
            precondition(files[.idle] != nil, "a buddy needs its idle file")
            self.id = id
            self.files = files
            self.offsets = offsets
        }

        /// A buddy with only its idle file (snapshots, tests).
        init(id: String, url: URL) { self.init(id: id, files: [.idle: url]) }
    }

    /// Oldest first, so a new one lands next to the + tile.
    private(set) var entries: [Entry]
    /// Why the last file was turned down; empty after one is taken.
    private(set) var rejection: [String] = []
    /// nil: nothing is read or saved (snapshots, tests).
    private let folder: URL?

    private static let offsetsFile = "offsets.json"

    init(folder: URL?, entries: [Entry] = [], rejection: [String] = []) {
        self.folder = folder
        self.entries = entries
        self.rejection = rejection
        guard let folder else { return }
        Self.migrate(folder)
        let dirs = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        self.entries = dirs.compactMap(Self.load).sorted { a, b in
            // The idle file's age: moving it into its folder (`migrate`) keeps it, where the folder's own would be today.
            let (da, db) = (a.url.creationDate, b.url.creationDate)
            return da == db ? a.id.localizedStandardCompare(b.id) == .orderedAscending : da < db
        }
    }

    static func live() -> CustomBuddyStore { CustomBuddyStore(folder: .applicationSupportDirectory.appending(path: "MyWorkDock/Buddies")) }
    static func sample(_ entries: [Entry] = [], rejection: [String] = []) -> CustomBuddyStore { CustomBuddyStore(folder: nil, entries: entries, rejection: rejection) }

    func entry(_ id: String?) -> Entry? { entries.first { $0.id == id } }

    /// Checks the file and, if it passes, keeps exactly the bytes that were checked (so the original can move or change) as a new
    /// buddy's idle file. Returns the new buddy's id; nil with `rejection` set when it is turned down.
    @discardableResult
    func add(from source: URL) -> String? {
        guard let folder else { return nil }
        guard entries.count < BuddyFileCheck.Limits.library else {
            return refuse("The library is full (\(BuddyFileCheck.Limits.library) buddies). Remove one first.")
        }
        guard let data = checked(source) else { return nil }
        let id = freeName(for: source.deletingPathExtension().lastPathComponent, in: folder)
        guard let url = write(data, as: .idle, of: id) else { return nil }
        rejection = []
        entries.append(Entry(id: id, url: url))
        return id
    }

    /// Gives buddy `id` a file for `state` (replacing what it had), checked like a new buddy. False with `rejection` set when it is
    /// turned down.
    @discardableResult
    func setFile(_ state: BuddyState, of id: String, from source: URL) -> Bool {
        guard folder != nil, let n = entries.firstIndex(where: { $0.id == id }), let data = checked(source),
              let url = write(data, as: state, of: id) else { return false }
        rejection = []
        entries[n].files[state] = url
        return true
    }

    /// Takes the glance or the nap away again; the idle file stays (removing that is removing the buddy).
    func removeFile(_ state: BuddyState, of id: String) {
        guard state != .idle, let n = entries.firstIndex(where: { $0.id == id }), let url = entries[n].files[state] else { return }
        if folder != nil { try? FileManager.default.removeItem(at: url) }
        entries[n].files[state] = nil
        rejection = []
        LottieAnimationCache.shared?.clearCache()
    }

    /// Moves one state of buddy `id`, kept within `Geo.Buddy.States`' range. A sample store keeps it in memory.
    func setOffset(_ state: BuddyState, of id: String, to point: CGPoint) {
        guard let n = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[n].offsets[state] = point
        guard let folder, let data = try? JSONEncoder().encode(entries[n].offsets) else { return }
        try? data.write(to: folder.appending(path: id).appending(path: Self.offsetsFile), options: .atomic)
    }

    func remove(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        if let folder { try? FileManager.default.removeItem(at: folder.appending(path: id)) }
        entries.removeAll { $0.id == id }
        rejection = []
        LottieAnimationCache.shared?.clearCache()
    }

    // MARK: Files

    /// The file's bytes when they pass the check; nil with `rejection` set otherwise.
    private func checked(_ source: URL) -> Data? {
        guard let data = try? Data(contentsOf: source) else {
            _ = refuse("Could not read the file.")
            return nil
        }
        let verdict = BuddyFileCheck.check(data)
        guard verdict.accepted else {
            rejection = verdict.reasons
            return nil
        }
        return data
    }

    private func write(_ data: Data, as state: BuddyState, of id: String) -> URL? {
        guard let folder else { return nil }
        let dir = folder.appending(path: id)
        let url = dir.appending(path: state.fileName)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            _ = refuse("Could not save it: \(error.localizedDescription)")
            return nil
        }
        LottieAnimationCache.shared?.clearCache() // it keeps animations by path, and a replaced file has the same one
        return url
    }

    private func refuse(_ reason: String) -> String? {
        rejection = [reason]
        return nil
    }

    /// One buddy's folder as it is on disk now, every file checked again.
    private static func load(_ dir: URL) -> Entry? {
        let id = dir.lastPathComponent
        var files: [BuddyState: URL] = [:]
        for state in BuddyState.allCases {
            let url = dir.appending(path: state.fileName)
            guard let data = try? Data(contentsOf: url) else { continue }
            guard BuddyFileCheck.check(data).accepted else {
                NSLog("MyWorkDock: custom buddy %@/%@ no longer passes the check, left out", id, state.fileName)
                continue
            }
            files[state] = url
        }
        guard files[.idle] != nil else { return nil }
        let offsets = (try? Data(contentsOf: dir.appending(path: offsetsFile))).flatMap { try? JSONDecoder().decode(BuddyOffsets.self, from: $0) }
        return Entry(id: id, files: files, offsets: offsets ?? BuddyOffsets())
    }

    /// The first version kept each buddy as one `<name>.json` in the folder: each becomes `<name>/idle.json`. A name already taken by a
    /// folder keeps its loose file where it is.
    private static func migrate(_ folder: URL) {
        let fm = FileManager.default
        let loose = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { $0.pathExtension == "json" }
        for file in loose {
            let dir = folder.appending(path: file.deletingPathExtension().lastPathComponent)
            guard !fm.fileExists(atPath: dir.path) else { continue }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: false)
                try fm.moveItem(at: file, to: dir.appending(path: BuddyState.idle.fileName))
            } catch {
                NSLog("MyWorkDock: could not move custom buddy %@ into its folder: %@", file.lastPathComponent, error.localizedDescription)
            }
        }
    }

    // MARK: Names

    /// The file's own name, kept to letters, digits, spaces, `-` and `_` (it becomes a folder name here), numbered when it is taken by a
    /// buddy or by anything else in the folder.
    private func freeName(for stem: String, in folder: URL) -> String {
        let kept = String(stem.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0) ? Character($0) : "-" })
        let trimmed = String(kept.trimmingCharacters(in: CharacterSet(charactersIn: " -")).prefix(40))
        let name = trimmed.isEmpty ? "Buddy" : trimmed
        let taken = Set(entries.map { $0.id.lowercased() }) // the file system may not tell Cat from cat
        func free(_ n: String) -> Bool { !taken.contains(n.lowercased()) && !FileManager.default.fileExists(atPath: folder.appending(path: n).path) }
        guard !free(name) else { return name }
        var n = 2
        while !free("\(name) \(n)") { n += 1 }
        return "\(name) \(n)"
    }
}

private extension URL {
    var creationDate: Date { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast }
}
