import Lottie
import SwiftUI

/// What a custom buddy file has to be, and the check every file passes before the app plays it. The buddy is on screen all day, so a
/// file has to be one Lottie's Core Animation engine draws (the render server animates it; its main-thread engine would wake the app
/// for every frame), small, and made of nothing the buddy cannot show. The built-in files go through the same check.
enum BuddyFileCheck {
    /// Every number in one place: the checker, the open panel and Settings all say the same thing.
    enum Limits {
        static let bytes = 256 * 1024
        static let side: ClosedRange<Double> = 8...512
        /// Width over height.
        static let aspect: ClosedRange<Double> = 0.5...2
        static let framerate: ClosedRange<Double> = 1...60
        /// The bundled face is 28 s: its 4 s blink and 7 s glance share one file.
        static let seconds = 30.0
        static let layers = 30
        static let images = 4
        static let imageSide = 256.0
        /// Buddies the library keeps.
        static let library = 12
        static let summary = "Lottie .json · up to \(bytes / 1024) KB · loops of \(Int(seconds)) s or less · shapes and emoji"
    }

    /// Why a file was turned down (all of it, in order), or the animation it holds.
    struct Verdict {
        var reasons: [String]
        var animation: LottieAnimation?
        var accepted: Bool { reasons.isEmpty }
    }

    @MainActor
    static func check(_ data: Data) -> Verdict {
        if data.count > Limits.bytes { return Verdict(reasons: ["Over \(Limits.bytes / 1024) KB (this file is \((data.count + 1023) / 1024) KB)."]) }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return Verdict(reasons: ["Not a JSON file."]) }
        guard let json = parsed as? [String: Any] else { return Verdict(reasons: ["Not a Lottie animation."]) }
        let why = problems(json)
        guard why.isEmpty else { return Verdict(reasons: why) }
        guard let animation = try? LottieAnimation.from(data: data) else { return Verdict(reasons: ["Lottie could not read this animation."]) }
        let issues = playIssues(animation)
        return Verdict(reasons: issues, animation: issues.isEmpty ? animation : nil)
    }

    // MARK: What the file says

    /// The rules that need only the file's text. Nothing is rendered until these pass: a precomp that contains itself, say, must not
    /// reach Lottie.
    private static func problems(_ json: [String: Any]) -> [String] {
        func number(_ key: String) -> Double? { json[key] as? Double }
        guard let rate = number("fr"), let first = number("ip"), let last = number("op"), let width = number("w"), let height = number("h"),
              let layers = json["layers"] as? [[String: Any]] else { return ["Not a Lottie animation."] }
        var why: [String] = []

        if !Limits.side.contains(width) || !Limits.side.contains(height) {
            why.append("The canvas is \(Int(width)) × \(Int(height)); each side has to be \(Int(Limits.side.lowerBound)) to \(Int(Limits.side.upperBound)).")
        } else if !Limits.aspect.contains(width / height) {
            why.append("The canvas is \(Int(width)) × \(Int(height)); it can be at most twice as wide as tall, or the other way round.")
        }
        if !Limits.framerate.contains(rate) {
            why.append("The frame rate is \(Int(rate)); it has to be \(Int(Limits.framerate.lowerBound)) to \(Int(Limits.framerate.upperBound)).")
        } else if last <= first {
            why.append("It has no frames.")
        } else if (last - first) / rate > Limits.seconds {
            why.append("It runs \(String(format: "%.1f", (last - first) / rate)) s; the limit is \(Int(Limits.seconds)) s.")
        }

        if layers.count > Limits.layers { why.append("It has \(layers.count) layers; the limit is \(Limits.layers).") }
        var unsupported: [String] = []
        func note(_ what: String) { if !unsupported.contains(what) { unsupported.append(what) } }
        for layer in layers {
            switch layer["ty"] as? Int {
            case 2, 3, 4: break // image, null, shape
            case 0: note("precomps (flatten them)")
            case 1: note("solid layers")
            case 5: note("text layers")
            default: note("a layer type the buddy cannot draw")
            }
            if layer["tm"] != nil { note("time remapping") }
            if (layer["ddd"] as? Int) == 1 { note("3D layers") }
            if let effects = layer["ef"] as? [Any], !effects.isEmpty { note("effects") }
        }
        if usesExpressions(layers) { note("expressions") }
        if !unsupported.isEmpty { why.append("It uses \(unsupported.joined(separator: ", ")); the buddy cannot show that.") }

        why += imageProblems(json["assets"] as? [[String: Any]] ?? [])
        return why
    }

    /// An expression is a string under `x` on an animated property (easing handles use `x` for numbers).
    private static func usesExpressions(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return dictionary["x"] is String || dictionary.values.contains(where: usesExpressions)
        }
        if let array = value as? [Any] { return array.contains(where: usesExpressions) }
        return false
    }

    /// Images have to be inside the file, few and small; a precomp asset is as unwelcome as a precomp layer.
    private static func imageProblems(_ assets: [[String: Any]]) -> [String] {
        var why: [String] = []
        let images = assets.filter { $0["layers"] == nil }
        if images.count < assets.count { why.append("It has precomp assets; flatten them.") }
        if images.count > Limits.images { why.append("It has \(images.count) images; the limit is \(Limits.images).") }
        if images.contains(where: { !(($0["p"] as? String) ?? "").hasPrefix("data:image/") || !((($0["u"] as? String) ?? "").isEmpty) }) {
            why.append("An image is a separate file; images have to be embedded in the .json.")
        }
        if let big = images.first(where: { max($0["w"] as? Double ?? 0, $0["h"] as? Double ?? 0) > Limits.imageSide }) {
            why.append("An image is \(Int(big["w"] as? Double ?? 0)) × \(Int(big["h"] as? Double ?? 0)) px; the limit is \(Int(Limits.imageSide)) px a side.")
        }
        return why
    }

    // MARK: What Lottie says

    /// Plays the animation off screen on the Core Animation engine and returns what Lottie objects to. Lottie finds out that a file cannot
    /// be drawn this way only when the first frame is displayed, and then asserts (which stops a debug build): this logger records instead.
    @MainActor
    private static func playIssues(_ animation: LottieAnimation) -> [String] {
        var said: [String] = []
        let logger = LottieLogger(assert: { holds, message, _, _ in if !holds() { said.append(message()) } },
                                  assertionFailure: { message, _, _ in said.append(message()) },
                                  warn: { message, _, _ in said.append(message()) },
                                  info: { _ in })
        let view = LottieAnimationView(animation: animation, configuration: BuddyLottieConfig.live, logger: logger)
        view.frame = CGRect(origin: .zero, size: animation.size)
        view.play()
        display(view.layer)
        view.stop()
        return said.flatMap { issues(in: $0) }
    }

    /// The layers set the animation up when they are first displayed; nothing is on screen here, so ask for it.
    private static func display(_ layer: CALayer?) {
        layer?.layoutIfNeeded()
        layer?.displayIfNeeded()
        layer?.sublayers?.forEach(display)
    }

    /// Lottie lists each problem on a line of its own: "[where] what".
    private static func issues(in message: String) -> [String] {
        let lines = message.split(separator: "\n").map(String.init)
        let problems = lines.filter { $0.hasPrefix("[") }.map { "Cannot be drawn cheaply enough for an always-on buddy: \($0)" }
        return problems.isEmpty ? [lines.first ?? message] : problems
    }
}
