import SwiftUI
import XCTest
@testable import MyWorkDock

/// Manual clock for the model's 350 ms leave timer.
@MainActor
private final class Jobs {
    var pending: [@MainActor () -> Void] = []
    func schedule(_ work: @escaping @MainActor () -> Void) -> () -> Void {
        pending.append(work)
        return {}
    }
    func flush() {
        let run = pending
        pending = []
        run.forEach { $0() }
    }
}

@MainActor
final class BuddyTests: XCTestCase {
    private var model: NotchModel!
    private var jobs: Jobs!
    /// A 14" MacBook Air in its default mode.
    private let notch = CGSize(width: 156, height: 28)

    override func setUp() async throws {
        model = NotchModel(sample: true)
        jobs = Jobs()
        let jobs = jobs!
        model.schedule = { _, work in jobs.schedule(work) }
    }

    private func freshDefaults() -> UserDefaults {
        let name = "BuddyTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // MARK: Settings

    func testRawValuesAreStable() {
        // Stored in UserDefaults.
        XCTAssertEqual(BuddyStyle.allCases.map(\.rawValue), ["face", "pulse", "emoji", "custom"])
        XCTAssertEqual(BuddyMotion.allCases.map(\.rawValue), ["lively", "calm", "still"])
        XCTAssertEqual(BuddyEmoji.allCases.map(\.rawValue), ["wave", "sparkle", "robot", "cat", "eyes"])
        XCTAssertEqual(BuddyEmoji.allCases.map(\.glyph), ["👋", "✨", "🤖", "🐱", "👀"])
    }

    func testTheDesignedDefaultsAreOnFaceLivelyAndHiddenInFullScreen() {
        XCTAssertEqual(BuddyPrefs(), BuddyPrefs(on: true, style: .face, emoji: .wave, motion: .lively, hideInFullScreen: true))
        XCTAssertEqual(BuddyPrefs(defaults: freshDefaults()), BuddyPrefs()) // nothing saved yet
        XCTAssertEqual(model.buddy, BuddyPrefs())
    }

    func testPrefsRoundTripThroughDefaultsAndGarbageFallsBack() {
        let d = freshDefaults()
        let prefs = BuddyPrefs(on: false, style: .emoji, emoji: .cat, motion: .calm, hideInFullScreen: false)
        prefs.save(to: d)
        XCTAssertEqual(BuddyPrefs(defaults: d), prefs)
        d.set("nonsense", forKey: "buddyStyle")
        d.set("nonsense", forKey: "buddyMotion")
        XCTAssertEqual(BuddyPrefs(defaults: d).style, .face)
        XCTAssertEqual(BuddyPrefs(defaults: d).motion, .lively)
        XCTAssertEqual(BuddyPrefs(defaults: d).emoji, .cat)
    }

    func testSettingTheSameChoiceTwiceChangesNothing() {
        var calls = 0
        model.onChange = { calls += 1 }
        model.setBuddy(BuddyPrefs())
        XCTAssertEqual(calls, 0)
        model.setBuddy(BuddyPrefs(motion: .calm))
        model.setBuddy(BuddyPrefs(motion: .calm))
        XCTAssertEqual(calls, 1)
    }

    // MARK: Shell

    func testIdleGrowsByTheEarAndKeepsItsLeftEdgeOnTheHardwareOne() {
        let plain = Geo.hardwareNotchShell(notch)
        let g = model.geometry(notch: notch)
        XCTAssertEqual(g.width, plain.width + Geo.Buddy.ear)
        XCTAssertEqual(g.centerOffset - g.width / 2, plain.centerOffset - plain.width / 2, accuracy: 1e-9)
        XCTAssertEqual([g.height, g.radius, g.shoulder], [plain.height, plain.radius, plain.shoulder])
    }

    func testWithoutANotchThePillGrowsToo() {
        let g = model.geometry()
        XCTAssertEqual(g.width, Geo.idle.width + Geo.Buddy.ear)
        XCTAssertEqual(g.centerOffset - g.width / 2, -Geo.idle.width / 2, accuracy: 1e-9)
    }

    func testOffIsThePlainHardware() {
        model.setBuddy(BuddyPrefs(on: false))
        XCTAssertEqual(model.geometry(notch: notch), Geo.hardwareNotchShell(notch))
        XCTAssertEqual(model.geometry().width, Geo.idle.width)
        XCTAssertFalse(model.buddyShown())
    }

    func testOnlyAnIdleNotchHasABuddy() {
        XCTAssertTrue(model.buddyShown())
        model.bootingOverride = "iPhone 16 Plus" // live activity
        XCTAssertFalse(model.buddyShown())
        model.bootingOverride = nil
        model.pointer(inside: true) // peek
        XCTAssertFalse(model.buddyShown())
        let peek = model.geometry(notch: notch)
        model.setBuddy(BuddyPrefs(on: false))
        XCTAssertEqual(model.geometry(notch: notch), peek) // the same with or without the buddy
        model.setBuddy(BuddyPrefs())
        model.openPanel()
        XCTAssertFalse(model.buddyShown())
    }

    func testTheIdleShellIsAskedForWhateverTheModeIs() {
        // The window layer keeps a peek open while the pointer rests over the ear the idle shell had (a peek with no IP is narrower).
        let idle = model.geometry(notch: notch)
        model.pointer(inside: true)
        XCTAssertEqual(model.idleGeometry(notch: notch, on: nil), idle)
        model.openPanel()
        XCTAssertEqual(model.idleGeometry(notch: notch, on: nil), idle)
        model.setMenuBarHidden([1])
        XCTAssertEqual(model.idleGeometry(notch: notch, on: 1), Geo.hardwareNotchShell(notch))
        XCTAssertEqual(model.idleGeometry(notch: notch, on: 2), idle)
        model.setBuddy(BuddyPrefs(on: false))
        XCTAssertEqual(model.idleGeometry(notch: notch, on: 2), Geo.hardwareNotchShell(notch))
    }

    func testOtherDisplaysKeepTheirBuddyWhileOneDisplayPeeks() {
        model.setActiveDisplay(1)
        model.pointer(inside: true)
        XCTAssertFalse(model.buddyShown(on: 1))
        XCTAssertTrue(model.buddyShown(on: 2))
    }

    func testAFullScreenAppHidesTheBuddyOnThatDisplayOnly() {
        model.setMenuBarHidden([2])
        XCTAssertTrue(model.buddyShown(on: 1))
        XCTAssertFalse(model.buddyShown(on: 2))
        XCTAssertEqual(model.geometry(notch: notch, on: 2), Geo.hardwareNotchShell(notch))
        XCTAssertEqual(model.geometry(notch: notch, on: 1).width, Geo.hardwareNotchShell(notch).width + Geo.Buddy.ear)
        model.setBuddy(BuddyPrefs(hideInFullScreen: false)) // the switch decides
        XCTAssertTrue(model.buddyShown(on: 2))
        model.setBuddy(BuddyPrefs())
        model.setMenuBarHidden([])
        XCTAssertTrue(model.buddyShown(on: 2))
    }

    // MARK: First-launch hint

    func testTheHintSitsUnderTheBuddyUntilTheFirstHover() {
        XCTAssertFalse(model.hintShown()) // snapshots and tests start without it
        model.resetBuddyHint()
        XCTAssertTrue(model.hintShown())
        model.pointer(inside: true)
        XCTAssertFalse(model.hintShown())
        model.pointer(inside: false)
        jobs.flush()
        XCTAssertEqual(model.mode, .idle)
        XCTAssertFalse(model.hintShown()) // never again
    }

    func testOpeningThePanelEndsTheHintToo() {
        model.resetBuddyHint()
        model.openPanel()
        model.closePanel()
        XCTAssertFalse(model.hintShown())
    }

    func testABuddyThatWasNeverShownHasNotSaidHello() {
        model.resetBuddyHint()
        model.setBuddy(BuddyPrefs(on: false))
        model.pointer(inside: true)
        model.closePanel()
        model.setBuddy(BuddyPrefs())
        XCTAssertTrue(model.hintShown())
    }

    func testTheHintFollowsTheDisplayThePointerIsOn() {
        model.resetBuddyHint()
        model.setActiveDisplay(1)
        XCTAssertTrue(model.hintShown(on: 1))
        XCTAssertFalse(model.hintShown(on: 2))
        model.setActiveDisplay(2)
        XCTAssertTrue(model.hintShown(on: 2))
    }

    // MARK: Custom buddies

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    /// A folder for the library and a place the user's files are picked from; both are gone after the test.
    private func scratch() throws -> (library: URL, downloads: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "buddy-custom-\(UUID().uuidString)")
        let downloads = root.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root.appending(path: "Buddies"), downloads)
    }

    /// A bundled file (the face, unless said) saved as `name`, optionally with another canvas.
    private func download(_ name: String, in folder: URL, from builtIn: String = "buddy-face", canvas: (w: Double, h: Double)? = nil) throws -> URL {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(Bundle.main.url(forResource: builtIn, withExtension: "json")))) as? [String: Any])
        if let canvas { json["w"] = canvas.w; json["h"] = canvas.h }
        let url = folder.appending(path: name)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    func testTheCustomChoiceIsRemembered() {
        let d = freshDefaults()
        let prefs = BuddyPrefs(style: .custom, custom: "Round")
        prefs.save(to: d)
        XCTAssertEqual(BuddyPrefs(defaults: d), prefs)
        BuddyPrefs(style: .custom, custom: nil).save(to: d)
        XCTAssertNil(BuddyPrefs(defaults: d).custom)
        XCTAssertNil(BuddyPrefs(defaults: freshDefaults()).custom)
    }

    func testACustomBuddyDrawsAtItsOwnSizeUpToTheCap() throws {
        let (library, downloads) = try scratch()
        let store = CustomBuddyStore(folder: library)
        store.add(from: try download("Square.json", in: downloads, canvas: (60, 60)))
        store.add(from: try download("Wide.json", in: downloads, canvas: (300, 200)))
        store.add(from: try download("Same.json", in: downloads))
        XCTAssertEqual(BuddyAsset.custom(try XCTUnwrap(store.entry("Square"))).size, CGSize(width: 60, height: 60)) // 1 unit = 1 pt
        XCTAssertEqual(BuddyAsset.custom(try XCTUnwrap(store.entry("Wide"))).size, CGSize(width: 120, height: 80)) // shrunk to the cap
        XCTAssertEqual(BuddyAsset.custom(try XCTUnwrap(store.entry("Same"))).size, CGSize(width: 36, height: 28))
        XCTAssertEqual(BuddyAsset(.face, emoji: .wave).size, CGSize(width: 36, height: 28))
    }

    func testTheSetHasTheFilesTheBuddyHasAndTheBuiltInsOnlyIdle() throws {
        let (library, downloads) = try scratch()
        let store = CustomBuddyStore(folder: library)
        store.add(from: try download("Momo.json", in: downloads))
        store.setFile(.nap, of: "Momo", from: try download("nap.json", in: downloads, from: "buddy-pulse"))
        store.setOffset(.nap, of: "Momo", to: CGPoint(x: 4, y: 20))
        let set = BuddySet(BuddyPrefs(style: .custom, custom: "Momo"), library: store)
        XCTAssertEqual(Set(set.assets.keys), [.idle, .nap])
        XCTAssertEqual(set.assets[.nap]?.url?.lastPathComponent, "nap.json")
        XCTAssertEqual(set.offsets.nap, CGPoint(x: 4, y: 20))
        XCTAssertNotEqual(set.assets[.nap], set.idle, "each state is its own asset")
        let face = BuddySet(BuddyPrefs(), library: store)
        XCTAssertEqual(Set(face.assets.keys), [.idle])
        XCTAssertEqual(face.idle, BuddyAsset(.face, emoji: .wave))
    }

    func testTheScheduleGlancesNapsOrStays() {
        func next(glance: Bool = true, nap: Bool = true, bobbing: Bool = false, motion: BuddyMotion = .lively, toNap: Double = 600, gap: Double = 45) -> BuddyStep {
            .next(glance: glance, nap: nap, bobbing: bobbing, motion: motion, toNap: toNap, gap: gap)
        }
        XCTAssertEqual(next(), .glance(after: 45))
        XCTAssertEqual(next(motion: .calm), .glance(after: 90))
        XCTAssertEqual(next(toNap: 30), .nap(after: 30), "no glance that would run into the nap")
        XCTAssertEqual(next(toNap: -5), .nap(after: 0), "overdue: nap now")
        XCTAssertEqual(next(nap: false, toNap: -5), .glance(after: 45), "no nap file: it keeps glancing")
        XCTAssertEqual(next(glance: false), .nap(after: 600))
        XCTAssertEqual(next(glance: false, nap: false), .stay, "a built-in buddy just loops")
        XCTAssertEqual(next(bobbing: true), .nap(after: 600), "no glance while the hint bobs")
        XCTAssertEqual(next(nap: false, bobbing: true), .stay)
        XCTAssertEqual(next(motion: .still, toNap: -5), .stay, "Still shows the idle frame only")
    }

    func testHoveringOrOpeningRestartsTheNapClock() {
        let start = model.lastActive
        model.pointer(inside: true)
        XCTAssertGreaterThan(model.lastActive, start)
        let hovered = model.lastActive
        model.pointer(inside: true) // still in: not a new hover
        XCTAssertEqual(model.lastActive, hovered)
        model.openPanel()
        XCTAssertGreaterThan(model.lastActive, hovered)
    }

    func testTheAssetIsTheLibrarysFileOrTheFaceWhenItIsGone() throws {
        let (library, downloads) = try scratch()
        let store = CustomBuddyStore(folder: library)
        store.add(from: try download("Round.json", in: downloads))
        let shown = BuddyAsset(BuddyPrefs(style: .custom, custom: "Round"), library: store)
        XCTAssertEqual(shown.url?.lastPathComponent, "idle.json")
        XCTAssertEqual(shown.calmSpeed, 0.45)
        XCTAssertNotNil(shown.animation)
        for gone in [BuddyPrefs(style: .custom, custom: "Gone"), BuddyPrefs(style: .custom, custom: nil)] {
            XCTAssertEqual(BuddyAsset(gone, library: store), BuddyAsset(.face, emoji: .wave), "the face, not nothing")
        }
        XCTAssertEqual(BuddyAsset(BuddyPrefs(style: .pulse, custom: "Round"), library: store).file, "buddy-pulse") // only the Custom style looks
    }

    func testPickingAFileChecksKeepsAndShowsIt() async throws {
        let (library, downloads) = try scratch()
        let m = NotchModel(sample: true, customBuddies: CustomBuddyStore(folder: library))
        let picked = try download("Wave.json", in: downloads, from: "buddy-emoji-wave")
        m.pickBuddyFile = { picked }
        m.addCustomBuddy()
        XCTAssertTrue(m.picking) // the panel must stay while the picker is up
        await settle()
        XCTAssertFalse(m.picking)
        XCTAssertEqual(m.buddy.style, .custom)
        XCTAssertEqual(m.buddy.custom, "Wave")
        XCTAssertEqual(m.buddyAsset.url?.deletingLastPathComponent().lastPathComponent, "Wave")
        XCTAssertEqual(m.customBuddies.rejection, [])
    }

    func testCancellingOrAFileTurnedDownChangesNothing() async throws {
        let (library, downloads) = try scratch()
        let m = NotchModel(sample: true, customBuddies: CustomBuddyStore(folder: library))
        m.pickBuddyFile = { nil }
        m.addCustomBuddy()
        await settle()
        XCTAssertEqual(m.buddy, BuddyPrefs())
        XCTAssertEqual(m.customBuddies.rejection, [])
        let junk = downloads.appending(path: "junk.json")
        try Data("[]".utf8).write(to: junk)
        m.pickBuddyFile = { junk }
        m.addCustomBuddy()
        await settle()
        XCTAssertEqual(m.buddy, BuddyPrefs())
        XCTAssertEqual(m.customBuddies.rejection, ["Not a Lottie animation."])
        XCTAssertFalse(m.picking)
    }

    func testThePanelStaysOpenWhileTheFilePickerIsUp() async {
        var asks = 0
        var finish: CheckedContinuation<URL?, Never>?
        model.pickBuddyFile = { asks += 1; return await withCheckedContinuation { finish = $0 } }
        model.pointer(inside: true)
        model.addCustomBuddy()
        model.addCustomBuddy() // a second ask while it is up does nothing
        await settle()
        model.pointer(inside: false) // the picker took the pointer away
        jobs.flush()
        XCTAssertEqual(model.mode, .peek)
        XCTAssertEqual(asks, 1)
        finish?.resume(returning: nil)
        await settle()
        XCTAssertFalse(model.picking)
    }

    func testRemovingTheShownBuddyHandsOverToTheNewestThenToTheFace() async throws {
        let (library, downloads) = try scratch()
        let m = NotchModel(sample: true, customBuddies: CustomBuddyStore(folder: library))
        for name in ["a", "b", "c"] {
            let file = try download("\(name).json", in: downloads)
            m.pickBuddyFile = { file }
            m.addCustomBuddy()
            await settle()
        }
        XCTAssertEqual(m.buddy.custom, "c")
        m.removeCustomBuddy("a") // not the one shown
        XCTAssertEqual(m.buddy.custom, "c")
        m.removeCustomBuddy("c")
        XCTAssertEqual(m.buddy.style, .custom)
        XCTAssertEqual(m.buddy.custom, "b")
        m.removeCustomBuddy("b")
        XCTAssertEqual(m.buddy.style, .face)
        XCTAssertEqual(m.buddy.custom, nil)
        XCTAssertEqual(m.buddyAsset, BuddyAsset(.face, emoji: .wave))
    }

    func testTheTextsSayWhatTheCheckEnforces() {
        XCTAssertEqual(BuddyFileCheck.Limits.summary, "Lottie .json · up to 256 KB · loops of 30 s or less · shapes and emoji")
        XCTAssertEqual(BuddyBrief.steps.count, 5)
        XCTAssertTrue(BuddyBrief.steps[0].contains("30 s"))
        XCTAssertTrue(BuddyBrief.text.contains("30 seconds") && BuddyBrief.text.contains("36 × 28") && BuddyBrief.text.contains("120 × 120"))
    }

    // MARK: Colour

    /// WCAG relative luminance, from the colour's sRGB components.
    private func luminance(_ color: Color) throws -> Double {
        let c = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        func linear(_ v: CGFloat) -> Double { Double(v) <= 0.04045 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    private func contrast(_ a: Color, _ b: Color) throws -> Double {
        let (x, y) = (try luminance(a), try luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testTheShellIsTheThemesOwnWhateverTheBuddyDoes() {
        // Dark: black like the hardware. Light: the panel's grey, like the peek and the open panel it grows into.
        for theme in [ThemeMode.dark, .light] {
            let t = Tokens(mode: theme, tint: .lime)
            XCTAssertEqual(t.panel, theme == .dark ? Color(hex: 0x000000) : Color(hex: 0xF2F2F6))
        }
    }

    func testTheBuddyIsTheTintOnTheDarkShellAndAShadeOfItOnTheLightOne() throws {
        for tint in Tint.allCases {
            XCTAssertEqual(try luminance(Tokens(mode: .dark, tint: tint).buddy), try luminance(tint.color), accuracy: 1e-9, tint.name)
            XCTAssertLessThan(try luminance(Tokens(mode: .light, tint: tint).buddy), try luminance(tint.color), tint.name)
        }
    }

    func testEveryTintIsSeenOnItsShell() throws {
        for theme in [ThemeMode.dark, .light] {
            for tint in Tint.allCases {
                let t = Tokens(mode: theme, tint: tint)
                XCTAssertGreaterThanOrEqual(try contrast(t.buddy, t.panel), 3, "\(tint.name) on the \(theme) shell") // WCAG for graphics
            }
        }
    }

    // MARK: Animations

    /// The Lottie files in the app bundle, as plain JSON (the tests do not link Lottie a second time).
    private func json(_ asset: BuddyAsset) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: asset.file, withExtension: "json"), asset.file)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private var everyAsset: [BuddyAsset] {
        BuddyStyle.allCases.filter { $0 != .custom }.flatMap { style in
            style == .emoji ? BuddyEmoji.allCases.map { BuddyAsset(style, emoji: $0) } : [BuddyAsset(style, emoji: .wave)]
        } + [BuddyAsset.hello]
    }

    func testEveryBuddyIsAFileInTheBundleAtTheDesignedSize() {
        XCTAssertEqual(everyAsset.count, 8) // face, pulse, five emoji, the hint's wave
        for asset in everyAsset {
            let wanted = asset == .hello ? CGSize(width: 26, height: 23) : CGSize(width: Geo.Buddy.ear, height: Geo.Buddy.height)
            XCTAssertEqual(asset.size, wanted, asset.file)
        }
        XCTAssertEqual(BuddyAsset.hello.size.width - 2 * BuddyAsset.hello.margin, 20) // the glyph's own box
    }

    func testTheLoopsAreTheDesignsAndCalmPlaysThemSlower() throws {
        func seconds(_ asset: BuddyAsset) throws -> Double { try XCTUnwrap(asset.animation).duration }
        let face = BuddyAsset(.face, emoji: .wave), pulse = BuddyAsset(.pulse, emoji: .wave), emoji = BuddyAsset(.emoji, emoji: .cat)
        XCTAssertEqual(try seconds(face), 28, accuracy: 0.01) // seven blinks of 4 s, four glances of 7 s
        XCTAssertEqual(try seconds(pulse), 2, accuracy: 0.01)
        XCTAssertEqual(try seconds(emoji), 2.4, accuracy: 0.01)
        XCTAssertEqual(4 / face.speed(for: .calm), 9, accuracy: 1e-9) // Calm's blink
        XCTAssertEqual(2 / pulse.speed(for: .calm), 4, accuracy: 1e-9)
        XCTAssertEqual(2.4 / emoji.speed(for: .calm), 6, accuracy: 1e-9)
        XCTAssertEqual(face.speed(for: .lively), 1)
        XCTAssertEqual(face.speed(for: .still), 1)
    }

    func testTheBlinkIsInTheFile() throws {
        // budBlink: scaleY 1 until 93 % of 4 s, .15 at 96 % (frame 115.2 at 30 fps), open again at 100 %.
        let layers = try XCTUnwrap(try json(BuddyAsset(.face, emoji: .wave))["layers"] as? [[String: Any]])
        let eyes = try XCTUnwrap(layers.first { $0["nm"] as? String == "eyes" })
        let groups = try XCTUnwrap((eyes["shapes"] as? [[String: Any]])?.first?["it"] as? [[String: Any]])
        let tr = try XCTUnwrap(groups.first { $0["ty"] as? String == "tr" })
        let keys = try XCTUnwrap((tr["s"] as? [String: Any])?["k"] as? [[String: Any]])
        let shut = try XCTUnwrap(keys.first { abs(($0["t"] as? Double ?? 0) - 115.2) < 0.01 })
        XCTAssertEqual(shut["s"] as? [Double], [100, 15])
        XCTAssertEqual(keys.count, 22) // seven blinks of three stops, and the last open eye
    }

    func testTheStillFaceIsTheTintWithBlackEyes() throws {
        let blue = Color(hex: Tint.blue.hex)
        let image = try XCTUnwrap(BuddyStill.image(BuddyAsset(.face, emoji: .wave), tint: blue))
        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep.pixelsWide, 108) // 36 pt at 3x
        func pixel(_ x: Double, _ y: Double) -> [Int] { // points from the top left
            let c = rep.colorAt(x: Int(x * 3), y: Int(y * 3))?.usingColorSpace(.deviceRGB)
            return [c?.redComponent, c?.greenComponent, c?.blueComponent].map { Int(((($0 ?? 0) * 255)).rounded()) }
        }
        XCTAssertEqual(pixel(18, 20), [0x0A, 0x84, 0xFF], "the face is the tint, exactly")
        XCTAssertEqual(pixel(14.5, 13.5), [0, 0, 0], "an eye")
        XCTAssertEqual(rep.colorAt(x: 2, y: 2)?.alphaComponent, 0, "nothing around it")
        let other = try XCTUnwrap(BuddyStill.image(BuddyAsset(.face, emoji: .wave), tint: Color(hex: Tint.pink.hex)))
        XCTAssertFalse(other === image) // one image per tint
    }

    // MARK: Full screen

    private func window(_ owner: String, _ layer: Int, _ r: CGRect) -> [String: Any] {
        [kCGWindowOwnerName as String: owner, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: ["X": r.minX, "Y": r.minY, "Width": r.width, "Height": r.height] as [String: CGFloat]]
    }

    func testMenuBarWindowsAreTheWindowServersStripsOnLayer24() {
        let bar = CGRect(x: 0, y: 0, width: 1280, height: 29)
        let list = [window("Window Server", 24, bar), window("Window Server", 25, bar), window("Dock", 24, bar),
                    window("Window Server", 24, CGRect(x: 0, y: 0, width: 1280, height: 832))]
        XCTAssertEqual(ScreenWatcher.menuBars(list), [bar])
        XCTAssertEqual(ScreenWatcher.menuBars([]), [])
    }

    func testADisplayWithNoBarOnItsTopStripIsWithoutOne() {
        let strips: [DisplayID: CGRect] = [1: CGRect(x: 0, y: 0, width: 1280, height: 40), 2: CGRect(x: 1280, y: -200, width: 1920, height: 40)]
        let bar = CGRect(x: 0, y: 0, width: 1280, height: 29)
        XCTAssertEqual(ScreenWatcher.displaysWithoutBar([bar], strips: strips), [2])
        XCTAssertEqual(ScreenWatcher.displaysWithoutBar([], strips: strips), [1, 2])
        // Sliding in during a Space change counts, a bar parked above the display or a sliver of one does not.
        let sliding = [CGRect(x: -596, y: 0, width: 1280, height: 29), CGRect(x: 748, y: 0, width: 1280, height: 29)]
        XCTAssertEqual(ScreenWatcher.displaysWithoutBar(sliding, strips: strips), [2])
        XCTAssertEqual(ScreenWatcher.displaysWithoutBar([CGRect(x: 0, y: -29, width: 1280, height: 29)], strips: strips), [1, 2])
        XCTAssertEqual(ScreenWatcher.displaysWithoutBar([CGRect(x: 1200, y: 0, width: 1280, height: 29)], strips: strips), [1, 2])
    }
}
