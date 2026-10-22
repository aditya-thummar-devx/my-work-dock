import XCTest
@testable import MyWorkDock

/// The library of custom buddies on disk, in a temporary folder.
@MainActor
final class CustomBuddyStoreTests: XCTestCase {
    private var root: URL!
    private var library: URL { root.appending(path: "Buddies") }
    /// Where the user's files are when they pick them.
    private var downloads: URL { root.appending(path: "Downloads") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "buddy-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func store() -> CustomBuddyStore { CustomBuddyStore(folder: library) }

    /// A bundled animation saved as `name` in Downloads.
    @discardableResult
    private func download(_ name: String, from builtIn: String = "buddy-face") throws -> URL {
        let url = downloads.appending(path: name)
        try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: builtIn, withExtension: "json"))).write(to: url)
        return url
    }

    private func files() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []).sorted() }

    func testAddingKeepsACopyOfTheCheckedFile() throws {
        let s = store()
        let original = try download("Wave.json", from: "buddy-emoji-wave")
        XCTAssertEqual(s.add(from: original), "Wave")
        XCTAssertEqual(s.entries.map(\.id), ["Wave"])
        XCTAssertEqual(files(), ["Wave.json"])
        XCTAssertEqual(s.rejection, [])
        try FileManager.default.removeItem(at: original) // the original can go
        XCTAssertEqual(s.entry("Wave")?.url.lastPathComponent, "Wave.json")
        XCTAssertNotNil(s.entry("Wave").flatMap { try? Data(contentsOf: $0.url) })
        XCTAssertNil(s.entry("Cat"))
        XCTAssertNil(s.entry(nil))
    }

    func testNamesAreCleanedAndNumbered() throws {
        let s = store()
        XCTAssertEqual(s.add(from: try download("Cat!.json")), "Cat")
        XCTAssertEqual(s.add(from: try download("cat.json")), "cat 2") // the file system may not tell Cat from cat
        XCTAssertEqual(s.add(from: try download("CAT.json")), "CAT 3")
        XCTAssertEqual(s.add(from: try download("!!!.json")), "Buddy")
        XCTAssertEqual(s.add(from: try download(String(repeating: "x", count: 60) + ".json")), String(repeating: "x", count: 40))
        XCTAssertEqual(s.add(from: try download("a:b c.json")), "a-b c")
    }

    func testATurnedDownFileChangesNothing() throws {
        let s = store()
        let junk = downloads.appending(path: "junk.json")
        try Data("not an animation".utf8).write(to: junk)
        XCTAssertNil(s.add(from: junk))
        XCTAssertEqual(s.rejection, ["Not a JSON file."])
        XCTAssertEqual(s.entries, [])
        XCTAssertEqual(files(), [])
        XCTAssertNotNil(s.add(from: try download("ok.json"))) // the next good one clears the note
        XCTAssertEqual(s.rejection, [])
        XCTAssertNil(s.add(from: downloads.appending(path: "missing.json")))
        XCTAssertEqual(s.rejection, ["Could not read the file."])
        XCTAssertEqual(files(), ["ok.json"])
    }

    func testTheLibraryHoldsTwelve() throws {
        let s = store()
        for n in 0..<BuddyFileCheck.Limits.library { XCTAssertNotNil(s.add(from: try download("b\(n).json"))) }
        XCTAssertNil(s.add(from: try download("one-more.json")))
        XCTAssertTrue(s.rejection[0].contains("library is full"), s.rejection.joined())
        XCTAssertEqual(s.entries.count, 12)
        s.remove("b0")
        XCTAssertNotNil(s.add(from: try download("one-more.json")))
    }

    func testRemovingDeletesTheFile() throws {
        let s = store()
        s.add(from: try download("a.json"))
        s.add(from: try download("b.json"))
        s.remove("a")
        XCTAssertEqual(s.entries.map(\.id), ["b"])
        XCTAssertEqual(files(), ["b.json"])
        s.remove("nothing") // not there: nothing happens
        XCTAssertEqual(s.entries.count, 1)
    }

    func testALaterLaunchFindsThemOldestFirstAndLeavesOutWhatNoLongerPasses() throws {
        let first = store()
        for name in ["b", "a", "c"] { first.add(from: try download("\(name).json")) }
        for (n, name) in ["b", "a", "c"].enumerated() { // creation dates, so the order does not depend on the clock
            try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: Double(n))], ofItemAtPath: library.appending(path: "\(name).json").path)
        }
        try Data("{}".utf8).write(to: library.appending(path: "broken.json")) // put there by hand
        try Data("x".utf8).write(to: library.appending(path: "notes.txt"))
        let later = store()
        XCTAssertEqual(later.entries.map(\.id), ["b", "a", "c"])
        XCTAssertEqual(files(), ["a.json", "b.json", "broken.json", "c.json", "notes.txt"]) // nothing was deleted
    }

    func testASampleStoreSavesNothing() throws {
        let entry = CustomBuddyStore.Entry(id: "Sample", url: try XCTUnwrap(Bundle.main.url(forResource: "buddy-face", withExtension: "json")))
        let s = CustomBuddyStore.sample([entry])
        XCTAssertEqual(s.entries, [entry])
        XCTAssertNil(s.add(from: try download("x.json")))
        XCTAssertEqual(files(), [])
        s.remove("Sample")
        XCTAssertEqual(s.entries, [])
    }
}
