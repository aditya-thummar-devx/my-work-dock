import SwiftUI

extension SnippetKind {
    /// Commands are mono, prompts and links use the regular UI font (DESIGN_SPEC §5 Notes › Prompts).
    var font: Font { self == .commands ? Typo.mono(13) : Typo.ui(13) }
}

/// Notes › Commands, Prompts and Links: the add field and the grouped list, one view for all kinds.
struct SnippetScreen: View {
    var store: SnippetStore
    /// Commands only: nil on Prompts and Links, which have no Run.
    var runner: CommandRunner?
    var onRun: (Int) -> Void = { _ in }
    var onUnlock: (Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: Geo.Surface.fieldGap) {
            if store.kind == .prompts { PromptAddBar(store: store) } else { SnippetAddBar(store: store) }
            if store.items.isEmpty {
                EmptyState(title: store.kind.emptyTitle, message: store.kind.emptyHint)
                    .padding(.bottom, Geo.Surface.fieldGap) // same flex gap as TodoView's empty state
            } else if store.isSearching && store.visibleItems.isEmpty {
                EmptyState(message: store.emptyText, action: "Clear search", onAction: store.closeSearch)
                // The prototype's empty list still draws its 2 pt border + fill under the box (and keeps its flex gap).
                GroupedList(count: 0, rowHeight: Geo.Row.snippetHeight) { _ in EmptyView() }
            } else {
                SnippetList(store: store, runner: runner, onRun: onRun, onUnlock: onUnlock)
            }
        }
        .overlay(alignment: .bottom) {
            if store.hintShown {
                HintToast("Double-click a \(store.kind.noun) to copy it").padding(.bottom, 12).transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.hintShown)
    }
}

struct SnippetAddBar: View {
    @Bindable var store: SnippetStore
    @Environment(\.tokens) private var t

    var body: some View {
        FieldBar(text: $store.draft, placeholder: store.kind.placeholder, font: store.kind.font,
                 padLeading: 14, padTrailing: 6) {
            Text(store.kind.glyph).font(Typo.mono(14)).foregroundStyle(t.ink)
        } trailing: {
            DockButton(title: "Add", glyph: nil, metrics: .add, tone: .tint, weight: .bold, action: store.add)
        }
        .onSubmit(store.add)
    }
}

/// Prompts: a 2…5 row text area, `N lines` meta and Add at the bottom right. ↵ adds, ⇧↵ is a new line.
struct PromptAddBar: View {
    @Bindable var store: SnippetStore
    @Environment(\.tokens) private var t

    var body: some View {
        let rows = PromptRows.add(store.draft)
        HStack(alignment: .top, spacing: 10) {
            Text(store.kind.glyph).font(Typo.mono(14)).foregroundStyle(t.ink)
                .frame(height: Geo.Prompt.lineHeight)
            DockTextArea(text: $store.draft, placeholder: "Write a prompt… ↵ to add, ⇧↵ for a new line", rows: rows, onCommit: store.add)
            HStack(spacing: Geo.Prompt.metaGap) {
                Text(PromptRows.meta(store.draft)).font(Typo.ui(Geo.Prompt.metaFont)).foregroundStyle(t.faint).lineLimit(1).fixedSize()
                DockButton(title: "Add", glyph: nil, metrics: .add, tone: .tint, weight: .bold, action: store.add)
            }
            .frame(height: CGFloat(rows) * Geo.Prompt.lineHeight, alignment: .bottom)
        }
        .padding(.top, Geo.Prompt.addPad.top + 1)
        .padding(.leading, Geo.Prompt.addPad.leading + 1)
        .padding(.bottom, Geo.Prompt.addPad.bottom + 1)
        .padding(.trailing, Geo.Prompt.addPad.trailing + 1)
        .background(RoundedRectangle(cornerRadius: Geo.Surface.fieldRadius).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: Geo.Surface.fieldRadius).strokeBorder(t.border, lineWidth: 1))
    }
}

/// Prompts and Links search in the sub-nav: the shared search control, `N found`.
struct PromptNavTrailing: View {
    @Bindable var store: SnippetStore

    var body: some View {
        SearchControl(open: store.searchOpen, query: $store.query, placeholder: "Search \(store.kind.noun)s", count: store.foundText,
                      onOpen: store.openSearch, onClose: store.closeSearch)
    }
}

struct SnippetList: View {
    @Bindable var store: SnippetStore
    var runner: CommandRunner?
    var onRun: (Int) -> Void = { _ in }
    var onUnlock: (Int) -> Void = { _ in }

    var body: some View {
        let items = store.visibleItems
        GroupedList(count: items.count, rowHeight: Geo.Row.snippetHeight, scrolls: true, autoHeight: store.kind == .prompts) { i in
            let item = items[i]
            SnippetRow(kind: store.kind, text: item.text, copied: store.copiedId == item.id, editing: store.editId == item.id,
                       editText: $store.editDraft,
                       run: runner?.availability(of: item.text) ?? .none,
                       onTap: { store.tap(item.id) }, onOpen: { store.open(item.id) }, onRun: { onRun(item.id) }, onUnlock: { onUnlock(item.id) }, onCopy: { store.copy(item.id) }, onEdit: { store.startEdit(item.id) },
                       onDelete: { store.delete(item.id) }, onSave: store.saveEdit, onCancel: store.cancelEdit)
        }
    }
}
