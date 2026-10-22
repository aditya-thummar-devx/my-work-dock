import SwiftUI

enum NotesTab: String, CaseIterable {
    case todo, commands, prompts, links
}

/// Notes: sub-nav (TODO / Commands / Prompts / Links) plus the active tab's content. Fills the open panel between the top row and the footer.
struct NotesScreen: View {
    var model: NotchModel
    @Environment(\.tokens) private var t
    /// Coordinate space of the Notes area: where the edited todo's tag button reports its frame.
    static let space = "notes"
    @State private var editTagButton = CGRect.zero

    var body: some View {
        VStack(spacing: 0) {
            SubNavRow(items: [SubTabItem("todo", "TODO", count: model.notes.leftCount),
                              SubTabItem("commands", "Commands", count: model.commands.items.count),
                              SubTabItem("prompts", "Prompts", count: model.prompts.items.count),
                              SubTabItem("links", "Links", count: model.links.items.count)]
                          .filter { model.enabledNotesTabs.map(\.rawValue).contains($0.id) },
                      selection: model.notesTab.rawValue,
                      onSelect: { model.setNotesTab(NotesTab(rawValue: $0) ?? .todo) }) {
                switch model.notesTab {
                case .todo: TodoNavTrailing(store: model.notes)
                case .commands: Text("One line each · copy, edit or delete").font(Typo.ui(12)).foregroundStyle(t.faint)
                case .prompts: PromptNavTrailing(store: model.prompts)
                case .links: PromptNavTrailing(store: model.links)
                }
            }
            .padding(.top, Geo.Chrome.subNavTop)

            Group {
                switch model.notesTab {
                case .todo: TodoView(store: model.notes, bridge: model.todoBridge)
                case .commands: SnippetScreen(store: model.commands, runner: model.runner, onRun: model.runCommand, onUnlock: model.unlockCommand, onFolder: model.changeCommandFolder)
                case .prompts: SnippetScreen(store: model.prompts)
                case .links: SnippetScreen(store: model.links)
                }
            }
            .padding(.top, Geo.Chrome.contentTop)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(EditTagButtonFrameKey.self) { editTagButton = $0 }
        .overlay(alignment: .topTrailing) {
            if model.notesTab == .todo { TodoMenus(store: model.notes, editTagButton: editTagButton) }
        }
    }
}

// MARK: TODO

/// Tag and filter dropdowns. Drawn over the whole Notes area, not over their buttons: they stay inside their
/// parent's bounds (so clicks reach them) and above the list. Offsets are from the area's top-trailing corner.
struct TodoMenus: View {
    @Bindable var store: NotesStore
    /// Frame of the edited todo's tag button in the Notes area; its menu opens right under (or over) it.
    var editTagButton = CGRect.zero
    @Environment(\.tokens) private var t

    private func options(counts: Bool, editable: Bool = false) -> [TagMenuOption] {
        store.tagOrder.map {
            TagMenuOption(id: $0, label: "#\($0)", dot: TagPalette.dot($0, custom: store.customColor($0), in: t),
                          count: counts ? store.count(of: $0) : nil, editable: editable)
        }
    }

    /// `New tag` and, once there is a tag to manage, `Manage`.
    private var footer: some View {
        NewTagButton(action: { store.openTagForm() },
                     trailing: store.tagOrder.isEmpty ? nil : ("Manage", .pencil, store.openTagManage))
    }

    /// The name + colour popup, else the manage list (every tag with edit / delete, shared by both menus), else the picker list.
    @ViewBuilder private func menu<L: View>(width: CGFloat, @ViewBuilder list: () -> L) -> some View {
        if store.tagFormOpen {
            TagFormPopover(name: $store.newTag, hex: $store.tagHex, editing: store.editingTag != nil, canSave: store.canAddNewTag,
                           width: width, onSave: store.saveTagForm, onCancel: store.cancelTagForm)
        } else if store.tagManageOpen {
            TagMenu(title: "MANAGE TAGS", options: options(counts: true, editable: true), selected: "", width: width,
                    edit: TagMenuEditing(onEdit: { store.openTagForm(editing: $0) }, onDelete: store.deleteTag),
                    maxRows: Geo.Filter.maxRows) {
                NewTagButton(action: { store.openTagForm() }, trailing: ("Done", .check, store.closeTagManage))
            }
        } else {
            list()
        }
    }

    var body: some View {
        if store.filterMenuOpen || store.tagMenuOpen || store.editTagMenuOpen {
            // Outside click closes, like the claudex sort menu.
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: store.closeMenus)
        }
        if store.filterMenuOpen {
            // Right-aligned with the filter button, which sits left of the search circle (or the open search field).
            let searchWidth = store.searchOpen ? Geo.Search.todoWidth : Geo.Search.height
            menu(width: Geo.Filter.menuWidth) {
                TagMenu(title: "FILTER BY TAG",
                        options: [TagMenuOption(id: "all", label: "All", dot: nil, count: store.todos.count)] + options(counts: true),
                        selected: store.filterTag, width: Geo.Filter.menuWidth, onSelect: store.pickFilter,
                        maxRows: Geo.Filter.maxRows) {
                    footer
                }
            }
            .offset(x: -(searchWidth + Geo.SubTab.navGap), y: Geo.Chrome.subNavTop + Geo.Filter.menuTop)
        }
        if store.tagMenuOpen {
            menu(width: Geo.TagPicker.menuWidth) {
                TagMenu(title: "ASSIGN TAG",
                        options: [TagMenuOption(id: "", label: "No tag", dot: nil, count: nil)] + options(counts: false),
                        selected: store.todoTag ?? "", width: Geo.TagPicker.menuWidth,
                        onSelect: { store.pickTodoTag($0.isEmpty ? nil : $0) }) {
                    footer
                }
            }
            .offset(x: -Geo.TagPicker.menuRight,
                    y: Geo.Chrome.subNavTop + Geo.SubTab.height + Geo.Chrome.contentTop + Geo.TagPicker.menuTop)
        }
        if store.editTagMenuOpen, editTagButton != .zero {
            // Right edge on the button's, below it; in the lower half of the area it opens upward instead.
            GeometryReader { geo in
                let above = editTagButton.midY > geo.size.height / 2
                menu(width: Geo.TagPicker.menuWidth) {
                    TagMenu(title: "ASSIGN TAG",
                            options: [TagMenuOption(id: "", label: "No tag", dot: nil, count: nil)] + options(counts: false),
                            selected: store.editTag, width: Geo.TagPicker.menuWidth,
                            onSelect: { store.pickEditTag($0.isEmpty ? nil : $0) }) {
                        footer
                    }
                }
                .frame(width: Geo.TagPicker.menuWidth, height: above ? max(editTagButton.minY - 4, 0) : nil,
                       alignment: above ? .bottom : .top)
                .offset(x: max(editTagButton.maxX - Geo.TagPicker.menuWidth, 0), y: above ? 0 : editTagButton.maxY + 4)
            }
        }
    }
}

/// Sub-nav right side: tag filter dropdown, then search.
struct TodoNavTrailing: View {
    @Bindable var store: NotesStore

    var body: some View {
        TagFilterButton(store: store)
        SearchControl(open: store.searchOpen, query: $store.query, placeholder: "Search todos", count: store.foundText,
                      width: Geo.Search.todoWidth, onOpen: store.openSearch, onClose: store.closeSearch)
    }
}

/// `All tags ▾` / `● #bug ▾` (tinted with the tag colour) and its menu.
struct TagFilterButton: View {
    var store: NotesStore
    @Environment(\.tokens) private var t

    var body: some View {
        let tag = store.filterTag == "all" ? nil : store.filterTag
        let colors = tag.map { TagPalette.button($0, custom: store.customColor($0), in: t) }
        Button(action: store.toggleFilterMenu) {
            HStack(spacing: Geo.Filter.gap) {
                Icon(.funnel, size: Geo.Filter.icon)
                if let tag { Circle().fill(TagPalette.dot(tag, custom: store.customColor(tag), in: t)).frame(width: Geo.Filter.dot, height: Geo.Filter.dot) }
                Text(tag.map { "#\($0)" } ?? "All tags")
                Icon(.chevronDown, size: Geo.Filter.chevron, stroke: 2.8)
            }
            .font(Typo.ui(Geo.Filter.font, .semibold))
            .foregroundStyle(colors?.fg ?? t.text)
            .padding(.leading, Geo.Filter.padLeading)
            .padding(.trailing, Geo.Filter.padTrailing)
            .frame(height: Geo.Filter.height)
            .background(Capsule().fill(colors?.bg ?? t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.map { "Filter by tag: \($0). Change filter" } ?? "Filter by tag")
    }
}

struct TodoView: View {
    var store: NotesStore
    var bridge: TodoBridge

    var body: some View {
        VStack(spacing: Geo.Surface.fieldGap) {
            if bridge.showsBanner { ClaudeTodoBanner(bridge: bridge) }
            QuickAddBar(store: store)
            if store.visibleTodos.isEmpty {
                EmptyState(message: "No todos match \(store.emptyWhat).", action: "Clear filters", onAction: store.clearFilters)
                    .padding(.bottom, Geo.Surface.fieldGap) // the prototype's empty list still takes its flex gap
            } else {
                TodoList(store: store)
            }
        }
    }
}

/// Connects Claude Code to the TODO list (registers `mwd-mcp`), or repairs a registration that points elsewhere.
private struct ClaudeTodoBanner: View {
    var bridge: TodoBridge
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 14, border: t.accent.opacity(0.5), padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Icon(.chat, size: 14)
                    Text(bridge.status == .stale ? "Claude Code's todo connection needs an update." : "Add todos from Claude Code.")
                        .font(Typo.ui(12.5)).foregroundStyle(t.text)
                    Spacer(minLength: 0)
                    if bridge.status == .notInstalled {
                        DockButton(title: "Not now", glyph: nil, metrics: .card, tone: .secondaryQuiet, action: bridge.dismiss)
                    }
                    DockButton(title: bridge.status == .stale ? "Repair" : "Connect", glyph: nil, metrics: .card, tone: .tint,
                               busy: bridge.installing) { Task { await bridge.connect() } }
                }
                if let err = bridge.error {
                    Text(err).font(Typo.ui(12)).foregroundStyle(t.red).textSelection(.enabled)
                }
            }
        }
        .task { bridge.refresh() }
    }
}

struct QuickAddBar: View {
    @Bindable var store: NotesStore
    @Environment(\.tokens) private var t

    var body: some View {
        FieldBar(text: $store.draft, placeholder: "Add a todo, press Enter", font: Typo.ui(13.5),
                 padLeading: 14, padTrailing: 8) {
            Icon(.plus, size: 16, stroke: 2.4).foregroundStyle(t.ink)
        } trailing: {
            HStack(spacing: 8) {
                TagPickerButton(tag: store.todoTag, custom: store.todoTag.flatMap(store.customColor), action: store.toggleTagMenu)
                Button(action: store.addTodo) {
                    Text("↵").font(Typo.mono(12)).foregroundStyle(t.text2)
                        .padding(.horizontal, 9).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(t.btn2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add todo")
            }
        }
        .onSubmit(store.addTodo)
    }
}

/// `🏷 #bug ▾` in the quick-add row: the tag colour tints it; `Tag` while none is picked.
struct TagPickerButton: View {
    var tag: String?
    var custom: Color?
    /// What the tag is for, in the accessibility label.
    var noun = "new todo"
    var action: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        let colors = tag.map { TagPalette.button($0, custom: custom, in: t) }
        Button(action: action) {
            HStack(spacing: Geo.TagPicker.gap) {
                Icon(.tag, size: Geo.TagPicker.icon)
                Text(tag.map { "#\($0)" } ?? "Tag")
                Icon(.chevronDown, size: Geo.TagPicker.chevron, stroke: 2.8)
            }
            .font(Typo.ui(Geo.TagPicker.font, .semibold))
            .foregroundStyle(colors?.fg ?? t.text2)
            .padding(.leading, Geo.TagPicker.padLeading)
            .padding(.trailing, Geo.TagPicker.padTrailing)
            .frame(height: Geo.TagPicker.height)
            .background(RoundedRectangle(cornerRadius: Geo.TagPicker.radius).fill(colors?.bg ?? t.btn2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.map { "Tag for \(noun): \($0). Change tag" } ?? "Assign a tag to the \(noun)")
    }
}

/// Todos grouped by the day they were added: a heading and a grouped list per day, all in one scroller.
struct TodoList: View {
    @Bindable var store: NotesStore
    @Environment(\.tokens) private var t

    var body: some View {
        DockScroll {
            VStack(alignment: .leading, spacing: Geo.DayHeading.gap) {
                ForEach(store.sections) { section in
                    VStack(alignment: .leading, spacing: Geo.DayHeading.headerGap) {
                        HStack(spacing: 6) {
                            Text(section.title.uppercased())
                            Text("\(section.todos.count)").font(Typo.mono(Geo.DayHeading.font))
                        }
                        .font(Typo.ui(Geo.DayHeading.font, .semibold))
                        .foregroundStyle(t.faint)
                        .padding(.leading, 4)
                        GroupedList(count: section.todos.count, rowHeight: Geo.Row.todoHeight) { i in
                            let todo = section.todos[i]
                            TodoRow(todo: todo, tagColor: store.customColor(todo.tag), editing: store.editId == todo.id,
                                    editText: $store.editDraft, editTag: store.editTag, editTagColor: store.customColor(store.editTag),
                                    onEditTag: store.toggleEditTagMenu,
                                    onToggle: { store.toggle(todo.id) }, onEdit: { store.startEdit(todo.id) },
                                    onDelete: { store.delete(todo.id) }, onSave: store.saveEdit, onCancel: store.cancelEdit)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension Geo {
    /// Day heading above each todo list.
    enum DayHeading {
        static let font: CGFloat = 11
        static let gap: CGFloat = 14 // between one day's list and the next heading
        static let headerGap: CGFloat = 6
    }

    /// Filter dropdown button in the sub-nav and its menu.
    enum Filter {
        static let height: CGFloat = 32
        static let padLeading: CGFloat = 11
        static let padTrailing: CGFloat = 10
        static let gap: CGFloat = 7
        static let font: CGFloat = 12.5
        static let icon: CGFloat = 13
        static let dot: CGFloat = 7
        static let chevron: CGFloat = 10
        static let menuWidth: CGFloat = 232
        static let menuTop: CGFloat = 38 // below the sub-nav row's top edge
        static let maxRows = 7 // the list scrolls past this, keeping the menu inside the panel
    }

    /// Tag button in the quick-add row and its menu (offsets are from the row's border box).
    enum TagPicker {
        static let height: CGFloat = 28
        static let radius: CGFloat = 8
        static let padLeading: CGFloat = 9
        static let padTrailing: CGFloat = 8
        static let gap: CGFloat = 5
        static let font: CGFloat = 12
        static let icon: CGFloat = 12
        static let chevron: CGFloat = 10
        static let menuWidth: CGFloat = 232
        static let menuTop: CGFloat = 49 // `top: 48` from the padding edge + the 1 pt border
        static let menuRight: CGFloat = 41 // `right: 40` + the border
    }
}
