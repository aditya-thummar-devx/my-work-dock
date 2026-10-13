import AppKit

/// Tiny JSON persistence in Application Support. `url == nil` means in-memory only (snapshots, tests).
enum JSONFile {
    nonisolated static func url(_ name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "MyWorkDock/\(name)")
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Returns why it failed (shown in the footer), nil on success.
    @discardableResult
    static func save<T: Encodable>(_ value: T, to url: URL?) -> String? {
        guard let url else { return nil }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return nil
        } catch {
            NSLog("MyWorkDock: could not save \(url.lastPathComponent): \(error)")
            return error.localizedDescription
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
