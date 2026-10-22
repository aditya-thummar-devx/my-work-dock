#if DEBUG
import SwiftUI

/// Component fragments: one component (or one row of a screen) at its exact position in the open panel,
/// named `<reference>@<part>`. `compare.sh` compares only that region of `screenshots/**/<reference>.png`.
/// Rects are panel points: x = 20 is the panel's left padding, y = 54 the sub-nav, 100 / 134 the content.
/// Content ends at y = 411, 14 pt above the footer.
enum Fragments {
    typealias S = SnapshotRunner.State

    static let all: [S] = dark

    private static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: Dark

    private static let dark: [S] = [
        // Top row (IconButton): the chrome itself. No @maintabs: the menu tabs moved to the footer, centred, and no reference PNG shows them there.
        .chrome("03-notes-todo@topright", rect: r(534, 4, 206, 32)),

        // Notes sub-tabs (SubTabs): the left group only; filter / search / hint sit to its right
        .chrome("02-notes-todo@subtabs", .artboard, rect: r(20, 54, 324, 32)),
        .chrome("03-notes-commands@subtabs", .artboard, rect: r(20, 54, 324, 32)),
        .chrome("03b-notes-prompts@subtabs", .artboard, rect: r(20, 54, 324, 32)),
        .chrome("12-notes-commands@subtabs", rect: r(20, 54, 324, 32)) { SnapshotRunner.prototypeNotes($0, .commands) },
        .chrome("15-notes-prompts@subtabs", rect: r(20, 54, 324, 32)) { SnapshotRunner.prototypeNotes($0, .prompts) },

        // TODO: filter + search (sub-nav right), quick-add row with the tag button, list, empty state
        .chrome("03-notes-todo@navright", rect: r(596, 54, 148, 32)),
        .chrome("03-notes-todo@quickadd", rect: r(20, 100, 720, 44)),
        .chrome("03-notes-todo@list", rect: r(20, 154, 720, 257)),
        .chrome("06-todo-tag-assigned@quickadd", rect: r(20, 100, 720, 44)) {
            SnapshotRunner.designTag($0)
            $0.notes.draft = "Polish notch spring animation"
        },
        // Dropdowns: ASSIGN TAG (right edge 41 pt in from the area edge, 49 pt under the row) and FILTER BY TAG
        .chrome("04-todo-tag-menu@menu", rect: r(500, 146, 204, 262)) { $0.notes.toggleTagMenu() },
        .chrome("05-todo-tag-menu-new-tag@menu", rect: r(500, 146, 204, 262)) {
            $0.notes.toggleTagMenu()
            $0.notes.openTagForm()
            $0.notes.newTag = "design"
        },
        .chrome("08-todo-filter-menu@menu", rect: r(540, 90, 204, 208)) {
            SnapshotRunner.prototypeNotes($0, .todo)
            $0.notes.toggleFilterMenu()
        },
        .chrome("09-todo-filtered-bug@navright", rect: r(596, 54, 148, 32)) {
            SnapshotRunner.prototypeNotes($0, .todo)
            $0.notes.pickFilter("bug")
        },
        .chrome("07-todo-added-with-new-tag@list", rect: r(20, 154, 720, 257)) { SnapshotRunner.prototypeNotes($0, .todo) },
        .chrome("10-todo-search@navright", rect: r(388, 54, 356, 32)) {
            SnapshotRunner.prototypeNotes($0, .todo)
            $0.notes.openSearch()
            $0.notes.query = "pod"
        },
        .chrome("11-todo-search-empty@empty", rect: r(20, 154, 720, 257)) {
            SnapshotRunner.prototypeNotes($0, .todo)
            $0.notes.openSearch()
            $0.notes.query = "zzz"
        },

        // Prompts search: the field in the sub-nav, the empty state under the add bar (y = 166)
        .chrome("19-notes-prompts-search@search", rect: r(496, 54, 248, 32)) {
            SnapshotRunner.prototypeNotes($0, .prompts)
            SnapshotRunner.addedPrompt($0)
            $0.prompts.openSearch()
            $0.prompts.query = "release"
        },
        .chrome("19-notes-prompts-search@list", rect: r(20, 166, 720, 245)) {
            SnapshotRunner.prototypeNotes($0, .prompts)
            SnapshotRunner.addedPrompt($0)
            $0.prompts.openSearch()
            $0.prompts.query = "release"
        },
        .chrome("20-notes-prompts-search-empty@empty", rect: r(20, 166, 720, 245)) {
            SnapshotRunner.prototypeNotes($0, .prompts)
            SnapshotRunner.addedPrompt($0)
            $0.prompts.openSearch()
            $0.prompts.query = "zzz"
        },

        // Commands add field + list (SnippetScreen): y = 100 add field, 154 list
        .chrome("12-notes-commands@add", rect: r(20, 100, 720, 44)) { SnapshotRunner.prototypeNotes($0, .commands) },
        .chrome("12-notes-commands@list", rect: r(20, 154, 720, 257)) { SnapshotRunner.prototypeNotes($0, .commands) },
        .chrome("13-notes-commands-editing@list", rect: r(20, 154, 720, 257)) {
            SnapshotRunner.prototypeNotes($0, .commands)
            $0.commands.startEdit(1)
        },
        .chrome("14-notes-commands-copied@list", rect: r(20, 154, 720, 257)) {
            SnapshotRunner.prototypeNotes($0, .commands)
            $0.commands.showCopied(1)
        },
    ]
}
#endif
