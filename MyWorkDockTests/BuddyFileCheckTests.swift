import XCTest
@testable import MyWorkDock

/// The check a custom buddy file passes. Fixtures are the bundled face with one thing changed.
@MainActor
final class BuddyFileCheckTests: XCTestCase {
    private let builtIns = ["buddy-face", "buddy-pulse", "buddy-emoji-wave", "buddy-emoji-sparkle", "buddy-emoji-robot",
                            "buddy-emoji-cat", "buddy-emoji-eyes", "buddy-hello"]

    private func builtIn(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"), name))
    }

    /// The face with `edit` applied to its JSON.
    private func face(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: builtIn("buddy-face")) as? [String: Any])
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func reasons(_ data: Data) -> String { BuddyFileCheck.check(data).reasons.joined(separator: " | ") }

    private func layers(_ json: [String: Any]) -> [[String: Any]] { json["layers"] as? [[String: Any]] ?? [] }

    // MARK: Accepted

    func testEveryBundledFileIsAccepted() throws {
        for name in builtIns {
            let verdict = BuddyFileCheck.check(try builtIn(name))
            XCTAssertEqual(verdict.reasons, [], name)
            XCTAssertNotNil(verdict.animation, name)
        }
    }

    // MARK: The file's text

    func testNotJSONAndNotLottie() {
        XCTAssertEqual(BuddyFileCheck.check(Data("hello".utf8)).reasons, ["Not a JSON file."])
        XCTAssertEqual(BuddyFileCheck.check(Data(#"{"a": 1}"#.utf8)).reasons, ["Not a Lottie animation."])
        XCTAssertEqual(BuddyFileCheck.check(Data("[1, 2]".utf8)).reasons, ["Not a Lottie animation."]) // JSON, but not an animation
    }

    func testTooBig() throws {
        let padded = try face { $0["nm"] = String(repeating: "x", count: BuddyFileCheck.Limits.bytes) }
        XCTAssertTrue(reasons(padded).hasPrefix("Over 256 KB"), reasons(padded))
    }

    func testCanvasAndTime() throws {
        XCTAssertTrue(reasons(try face { $0["w"] = 600; $0["h"] = 400 }).contains("each side has to be 8 to 512"))
        XCTAssertTrue(reasons(try face { $0["w"] = 100; $0["h"] = 20 }).contains("at most twice as wide as tall"))
        XCTAssertTrue(reasons(try face { $0["fr"] = 120 }).contains("frame rate is 120"))
        XCTAssertTrue(reasons(try face { $0["op"] = 30 * 31 }).contains("runs 31.0 s; the limit is 30 s"))
        XCTAssertEqual(reasons(try face { $0["op"] = 30 * 30 }), "") // exactly the limit
        XCTAssertEqual(reasons(try face { $0["fr"] = 60; $0["op"] = 60 * 30 }), "") // the most frames the limits allow
        XCTAssertTrue(reasons(try face { $0["op"] = 0 }).contains("no frames"))
    }

    func testLayers() throws {
        let crowded = try face { json in
            let first = layers(json)[0]
            json["layers"] = Array(repeating: first, count: BuddyFileCheck.Limits.layers + 1)
        }
        XCTAssertTrue(reasons(crowded).contains("31 layers; the limit is 30"), reasons(crowded))
        let kinds = try face { json in
            var all = layers(json)
            for ty in [0, 1, 5, 9] { var l = all[0]; l["ty"] = ty; all.append(l) }
            json["layers"] = all
        }
        let said = reasons(kinds)
        for what in ["precomps", "solid layers", "text layers", "a layer type the buddy cannot draw"] { XCTAssertTrue(said.contains(what), said) }
        let extras = try face { json in
            var all = layers(json)
            all[0]["tm"] = ["a": 0, "k": 0]
            all[0]["ddd"] = 1
            all[0]["ef"] = [["ty": 5]]
            json["layers"] = all
        }
        for what in ["time remapping", "3D layers", "effects"] { XCTAssertTrue(reasons(extras).contains(what), reasons(extras)) }
    }

    func testExpressions() throws {
        let scripted = try face { json in
            var all = layers(json)
            var ks = all[0]["ks"] as? [String: Any] ?? [:]
            ks["r"] = ["a": 0, "k": 0, "x": "time * 10"]
            all[0]["ks"] = ks
            json["layers"] = all
        }
        XCTAssertTrue(reasons(scripted).contains("expressions"), reasons(scripted))
        XCTAssertEqual(reasons(try face()), "") // the easing handles' numeric `x` are not expressions
    }

    func testImagesHaveToBeEmbeddedFewAndSmall() throws {
        func image(_ id: String, p: String, u: String = "", side: Double = 64) -> [String: Any] { ["id": id, "w": side, "h": side, "u": u, "p": p, "e": 0] }
        let embedded = "data:image/png;base64,iVBORw0KGgo="
        XCTAssertTrue(reasons(try face { $0["assets"] = [image("a", p: "a.png", u: "images/")] }).contains("separate file"))
        XCTAssertTrue(reasons(try face { $0["assets"] = [image("a", p: "a.png")] }).contains("separate file"))
        XCTAssertTrue(reasons(try face { $0["assets"] = [image("a", p: embedded, side: 300)] }).contains("300 × 300 px"))
        let many = try face { $0["assets"] = (0..<5).map { image("i\($0)", p: embedded) } }
        XCTAssertTrue(reasons(many).contains("5 images; the limit is 4"), reasons(many))
        XCTAssertTrue(reasons(try face { $0["assets"] = [["id": "c", "layers": []]] }).contains("precomp assets"))
    }

    // MARK: What Lottie says

    /// A trim on a filled shape is something the Core Animation engine does not draw; the file's text gives no hint of it.
    func testAFileOnlyTheMainThreadEngineCanDrawIsRefused() throws {
        let trimmed = try face { json in
            var all = layers(json)
            let trim: [String: Any] = ["ty": "tm", "nm": "trim", "s": ["a": 0, "k": 0],
                                       "e": ["a": 1, "k": [["t": 0, "s": [0], "i": ["x": [1], "y": [1]], "o": ["x": [0], "y": [0]]], ["t": 30, "s": [100]]]],
                                       "o": ["a": 0, "k": 0], "m": 1]
            for i in all.indices {
                guard var shapes = all[i]["shapes"] as? [[String: Any]], var group = shapes.first, var items = group["it"] as? [[String: Any]],
                      items.contains(where: { $0["ty"] as? String == "fl" }) else { continue }
                items.insert(trim, at: items.count - 1) // before the group's transform
                group["it"] = items
                shapes[0] = group
                all[i]["shapes"] = shapes
                break
            }
            json["layers"] = all
        }
        let verdict = BuddyFileCheck.check(trimmed)
        XCTAssertNil(verdict.animation)
        XCTAssertTrue(verdict.reasons.joined().contains("trims to filled shapes"), reasons(trimmed))
        XCTAssertTrue(verdict.reasons.allSatisfy { $0.hasPrefix("Cannot be drawn cheaply enough for an always-on buddy: [") }, reasons(trimmed))
    }

    /// Whatever a file holds, the check answers and the app goes on: numbers swapped for junk of every type, two at a time, seeded.
    func testMutatedFilesNeverCrashTheCheck() throws {
        struct SplitMix64: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E3779B97F4A7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
                z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
                return z ^ (z >> 31)
            }
        }
        let text = String(decoding: try builtIn("buddy-face"), as: UTF8.self)
        let numbers = try NSRegularExpression(pattern: #"-?\d+(\.\d+)?([eE][-+]?\d+)?"#).matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertGreaterThan(numbers.count, 100)
        let junk = ["0", "-1", "1e9", "-1e308", "999999999999", "0.0000001", "null", "\"x\"", "[]", "{}", "true", "[1]"]
        var random = SplitMix64(state: 7)
        var turnedDown = 0
        for _ in 0..<400 {
            var mutated = text
            for match in (0..<2).map({ _ in numbers.randomElement(using: &random)! }).sorted(by: { $0.range.location > $1.range.location }) {
                guard let range = Range(match.range, in: mutated) else { continue }
                mutated.replaceSubrange(range, with: junk.randomElement(using: &random)!)
            }
            if !BuddyFileCheck.check(Data(mutated.utf8)).accepted { turnedDown += 1 }
        }
        XCTAssertGreaterThan(turnedDown, 0) // the mutations do bite
    }

    func testBrokenFilesNeverCrashTheCheck() throws {
        let whole = try face()
        for cut in stride(from: 0, to: whole.count, by: whole.count / 40) {
            XCTAssertFalse(BuddyFileCheck.check(whole.prefix(cut)).accepted, "cut at \(cut)")
        }
        XCTAssertFalse(BuddyFileCheck.check(Data()).accepted)
    }
}
