import Foundation

struct SessionGroup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

/// User-defined groups for the Sessions board, kept in MyWorkDock's own folder (Claude's
/// transcripts are never modified).
final class SessionGroups {
    private struct Data_: Codable {
        var groups: [SessionGroup] = []
        /// session id → group id
        var assignments: [String: String] = [:]
        var nextID = 0
    }

    private let file: URL?
    private var data = Data_()

    var groups: [SessionGroup] { data.groups }
    var assignments: [String: String] { data.assignments }

    init(file: URL?) {
        self.file = file
        if let file, let raw = try? Data(contentsOf: file) {
            if let d = try? JSONDecoder().decode(Data_.self, from: raw) { data = d }
            else { try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("bad")) }
        }
    }

    static func live() -> SessionGroups {
        SessionGroups(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyWorkDock/session-groups.json"))
    }

    func group(of session: String) -> String? {
        data.assignments[session].flatMap { id in data.groups.contains { $0.id == id } ? id : nil }
    }

    private func validName(_ name: String, except: String? = nil) throws -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw AgentError("Give the group a name.") }
        if data.groups.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame && $0.id != except }) {
            throw AgentError("A group called “\(n)” already exists.")
        }
        return String(n.prefix(60))
    }

    @discardableResult
    func create(_ name: String) throws -> SessionGroup {
        let g = SessionGroup(id: "g\(data.nextID + 1)", name: try validName(name))
        data.nextID += 1
        data.groups.append(g)
        save()
        return g
    }

    func rename(_ id: String, _ name: String) throws {
        let n = try validName(name, except: id)
        guard let i = data.groups.firstIndex(where: { $0.id == id }) else { throw AgentError("No such group.") }
        data.groups[i].name = n
        save()
    }

    /// Its sessions become ungrouped.
    func delete(_ id: String) throws {
        guard data.groups.contains(where: { $0.id == id }) else { throw AgentError("No such group.") }
        data.groups.removeAll { $0.id == id }
        data.assignments = data.assignments.filter { $0.value != id }
        save()
    }

    func assign(_ session: String, to group: String?) throws {
        if let group {
            guard data.groups.contains(where: { $0.id == group }) else { throw AgentError("No such group.") }
            data.assignments[session] = group
        } else {
            data.assignments[session] = nil
        }
        save()
    }

    /// Puts every ungrouped session into a group named after its project; returns how many moved.
    @discardableResult
    func autoGroup(_ sessions: [(id: String, project: String)]) -> Int {
        var moved = 0
        for (id, project) in sessions where group(of: id) == nil && !project.isEmpty && project != "unknown" {
            let gid = data.groups.first { $0.name.caseInsensitiveCompare(project) == .orderedSame }?.id
                ?? (try? create(project))?.id
            guard let gid else { continue }
            data.assignments[id] = gid
            moved += 1
        }
        save()
        return moved
    }

    private func save() {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(data).write(to: file, options: .atomic)
    }
}
