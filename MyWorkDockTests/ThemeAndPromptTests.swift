import XCTest
import AppKit
import SwiftUI
@testable import MyWorkDock

@MainActor
final class ThemeAndPromptTests: XCTestCase {
    // MARK: System theme

    func testSystemResolvesToMacOSAndExplicitModesIgnoreIt() {
        XCTAssertEqual(ThemeMode.system.resolved(systemIsDark: true), .dark)
        XCTAssertEqual(ThemeMode.system.resolved(systemIsDark: false), .light)
        XCTAssertEqual(ThemeMode.dark.resolved(systemIsDark: false), .dark)
        XCTAssertEqual(ThemeMode.light.resolved(systemIsDark: true), .light)
        XCTAssertEqual(ThemeMode.allCases, [.system, .dark, .light]) // popover order
    }

    func testPanelFlipsLiveWhenMacOSAppearanceChanges() {
        let model = NotchModel(sample: true)
        model.setTheme(.system)
        model.openPanel()
        model.appearance.set(isDark: true)
        XCTAssertTrue(model.tokens.isDark)
        XCTAssertFalse(model.lightOpen)
        model.appearance.set(isDark: false)
        XCTAssertFalse(model.tokens.isDark)
        XCTAssertTrue(model.lightOpen) // draws the light panel with the black notch cut-out
        model.setTheme(.dark)
        model.appearance.set(isDark: false)
        XCTAssertTrue(model.tokens.isDark) // an explicit choice ignores macOS
    }

    func testLiveObserverFollowsNSAppAppearance() async throws {
        defer { NSApp.appearance = nil }
        NSApp.appearance = NSAppearance(named: .aqua)
        let observer = AppearanceObserver.live()
        XCTAssertFalse(observer.isDark)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(observer.isDark)
        NSApp.appearance = NSAppearance(named: .aqua)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(observer.isDark)
    }

    // MARK: Prompt fields

    func testAddFieldRowsFollowLinesBetweenTwoAndFive() {
        XCTAssertEqual(PromptRows.add(""), 2)
        XCTAssertEqual(PromptRows.add("one"), 2)
        XCTAssertEqual(PromptRows.add("a\nb\nc"), 3)
        XCTAssertEqual(PromptRows.add("a\nb\nc\nd\ne\nf\ng"), 5)
    }

    func testEditRowsFollowLinesOrEverySeventyCharactersUpToSix() {
        XCTAssertEqual(PromptRows.edit("short"), 2)
        XCTAssertEqual(PromptRows.edit(String(repeating: "a", count: 140)), 2)
        XCTAssertEqual(PromptRows.edit(String(repeating: "a", count: 141)), 3)
        XCTAssertEqual(PromptRows.edit(String(repeating: "a", count: 300)), 5)
        XCTAssertEqual(PromptRows.edit(String(repeating: "a", count: 900)), 6)
        XCTAssertEqual(PromptRows.edit("1\n2\n3\n4"), 4)
    }

    func testLinesMetaOnlyAppearsOnceThereIsABreak() {
        XCTAssertEqual(PromptRows.meta("one line"), "")
        XCTAssertEqual(PromptRows.meta("a\nb"), "2 lines")
        XCTAssertEqual(PromptRows.meta("a\nb\nc"), "3 lines")
    }

    func testPromptKeepsInnerLineBreaksAndTrimsTheEnds() {
        let store = SnippetStore(.prompts, url: nil, seed: [])
        store.draft = "\n  First\n- second\n\n"
        store.add()
        XCTAssertEqual(store.items[0].text, "First\n- second")
        store.startEdit(1)
        XCTAssertEqual(store.editDraft, "First\n- second")
        store.editDraft = "A\nB\nC"
        store.saveEdit()
        XCTAssertEqual(store.items[0].text, "A\nB\nC")
    }

    func testSeedPromptsAreMultilineAndFiveOfThem() {
        XCTAssertEqual(SampleData.prompts.count, 5)
        XCTAssertTrue(SampleData.prompts[0].contains("\n"))
    }

    /// Return commits, Esc cancels (only when a cancel handler is set); ⇧↵ is handled by the AppKit default newline.
    func testTextAreaCommandsCommitAndCancel() {
        var commits = 0, cancels = 0
        var text = ""
        let rep = TextAreaRepresentable(text: Binding(get: { text }, set: { text = $0 }), color: .white, autofocus: false,
                                        onCommit: { commits += 1 }, onCancel: { cancels += 1 })
        let coordinator = TextAreaRepresentable.Coordinator(rep)
        let view = NSTextView()
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(commits, 1)
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(cancels, 1)
        XCTAssertFalse(coordinator.textView(view, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        view.string = "typed"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        XCTAssertEqual(text, "typed")

        let noCancel = TextAreaRepresentable.Coordinator(TextAreaRepresentable(text: .constant(""), color: .white, autofocus: false, onCommit: {}, onCancel: nil))
        XCTAssertFalse(noCancel.textView(view, doCommandBy: #selector(NSResponder.cancelOperation(_:)))) // add field: Esc falls through
    }
}
