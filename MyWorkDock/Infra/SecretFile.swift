import Foundation

/// A file only this user can read (mode 0600) and Time Machine skips: the Google token is a credential, unlike the other
/// JSON files. Written to a hidden sibling first and renamed over the target, so a crash never leaves half a token.
enum SecretFile {
    static func load(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    /// Returns why it failed, nil on success.
    @discardableResult
    static func save(_ data: Data, to url: URL) -> String? {
        let tmp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).tmp")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: tmp)
            guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                return "could not write \(tmp.lastPathComponent)"
            }
            var hidden = URLResourceValues()
            hidden.isExcludedFromBackup = true
            var target = tmp
            try target.setResourceValues(hidden)
            guard rename(tmp.path, url.path) == 0 else { return String(cString: strerror(errno)) }
            return nil
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return error.localizedDescription
        }
    }

    static func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
