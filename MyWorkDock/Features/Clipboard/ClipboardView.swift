import SwiftUI

/// Clipboard: one row (tag chips, search, Manage) over the history list. Fills the open panel between the top row and the footer.
struct ClipboardScreen: View {
    @Bindable var store: ClipboardStore
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(spacing: 0) {
            TopRow(store: store) {
                SearchControl(open: store.searchOpen, query: $store.query, placeholder: "Search clips", count: store.foundText,
                              onOpen: store.openSearch, onClose: store.closeSearch)
            }

            Group {
                if store.items.isEmpty {
                    EmptyState(title: "Nothing copied yet", message: "Copy some text and it shows up here.")
                        .padding(.bottom, Geo.Surface.fieldGap)
                } else if store.isFiltering && store.visibleItems.isEmpty {
                    EmptyState(message: store.emptyText, action: "Clear filter", onAction: store.clearFilters)
                } else {
                    let items = store.visibleItems
                    GroupedList(count: items.count, rowHeight: Geo.Row.snippetHeight, scrolls: true, autoHeight: true) { i in
                        let item = items[i]
                        ClipRow(item: item, color: item.tag.flatMap(store.customColor), copied: store.copiedId == item.id,
                                onTap: { store.tap(item.id) }, onCopy: { store.copy(item.id) }, onTag: { store.openTagPicker(item.id) },
                                onPin: { store.togglePin(item.id) }, onDelete: { store.delete(item.id) })
                    }
                }
            }
            .padding(.top, Geo.Chrome.contentTop)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .topTrailing) { tagMenu }
        .overlay(alignment: .bottom) {
            if store.hintShown { HintToast().padding(.bottom, 12).transition(.opacity.combined(with: .offset(y: 6))) }
        }
        .animation(.easeOut(duration: 0.15), value: store.hintShown)
        .animation(.easeOut(duration: Geo.popoverFade), value: store.tagMenuOpen)
    }

    // MARK: Tag menus (the same popups as Notes › TODO)

    private func options(editable: Bool) -> [TagMenuOption] {
        store.tags.map {
            TagMenuOption(id: $0, label: "#\($0)", dot: TagPalette.dot($0, custom: store.customColor($0), in: t),
                          count: editable ? store.count(of: $0) : nil, editable: editable)
        }
    }

    /// Under the search row, over a click-away scrim.
    @ViewBuilder private var tagMenu: some View {
        if store.tagMenuOpen {
            ZStack(alignment: .topTrailing) {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: store.closeMenus)
                menu.offset(y: Geo.Chrome.subNavTop + Geo.Filter.menuTop)
            }
            .transition(.opacity)
        }
    }

    /// The name + colour popup, else the manage list (every tag with edit / delete), else the assign list.
    @ViewBuilder private var menu: some View {
        let width = Geo.Filter.menuWidth
        if store.tagFormOpen {
            TagFormPopover(name: $store.newTag, hex: $store.tagHex, editing: store.editingTag != nil, canSave: store.canAddNewTag,
                           width: width, onSave: store.saveTagForm, onCancel: store.cancelTagForm)
        } else if store.tagManageOpen {
            TagMenu(title: "MANAGE TAGS", options: options(editable: true), selected: "", width: width,
                    edit: TagMenuEditing(onEdit: { store.openTagForm(editing: $0) }, onDelete: store.deleteTag),
                    maxRows: Geo.Filter.maxRows) {
                NewTagButton(action: { store.openTagForm() }, trailing: ("Done", .check, store.closeTagManage))
            }
        } else if let id = store.tagPickerId, let item = store.items.first(where: { $0.id == id }) {
            TagMenu(title: "ASSIGN TAG", options: [TagMenuOption(id: "", label: "No tag", dot: nil)] + options(editable: false),
                    selected: item.tag ?? "", width: width,
                    onSelect: { store.assign($0.isEmpty ? nil : $0, to: id) }, maxRows: Geo.Filter.maxRows) {
                NewTagButton(action: { store.openTagForm() },
                             trailing: store.tags.isEmpty ? nil : ("Manage", .pencil, store.openTagManage))
            }
        }
    }
}

/// Chips on the left (All, then one per tag; tapping a tag filters the list to it, again clears), then search, then `Manage`
/// at the right. With no tags yet only the search shows.
private struct TopRow<Search: View>: View {
    var store: ClipboardStore
    @ViewBuilder var search: Search
    @Environment(\.tokens) private var t
    /// Snapshots can't draw a ScrollView: they get the same chips, clipped.
    @Environment(\.staticRender) private var staticRender

    var body: some View {
        let chips = HStack(spacing: 6) {
            chip(nil)
            ForEach(store.tags, id: \.self) { chip($0) }
        }
        HStack(spacing: 8) {
            if store.tags.isEmpty {
                Spacer(minLength: 0)
            } else if staticRender {
                chips.frame(maxWidth: .infinity, alignment: .leading).clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) { chips }.frame(height: height)
            }
            search
            if !store.tags.isEmpty { manage }
        }
        .frame(height: Geo.SubTab.height)
        .padding(.top, Geo.Chrome.subNavTop)
    }

    private var height: CGFloat { 28 }

    private func chip(_ tag: String?) -> some View {
        let on = store.filterTag == tag
        let count = tag.map { store.count(of: $0) } ?? store.items.count
        let color = tag.map { TagPalette.dot($0, custom: store.customColor($0), in: t) }
        // Selected: solid (inverted for All, the tag colour for a tag). Idle: neutral pill, a tag shows its colour as a dot.
        let fill = on ? (color ?? t.text) : t.ctrl
        let fg = on ? (color == nil ? t.panel : Color(hex: 0x111114)) : t.text2
        return Button { store.pickFilter(tag) } label: {
            HStack(spacing: 6) {
                if let color, !on { Circle().fill(color).frame(width: 7, height: 7) }
                Text(tag.map { "#\($0)" } ?? "All").font(Typo.ui(12, .semibold))
                Text("\(count)").font(Typo.ui(11)).opacity(0.65)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag.map { "Tag \($0), \(count) clips" } ?? "All clips, \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Opens the manage list (edit colour / rename / delete tags) without assigning anything.
    private var manage: some View {
        Button(action: store.openTagManage) {
            HStack(spacing: 6) {
                Icon(.pencil, size: 11, stroke: 2.4)
                Text("Manage").font(Typo.ui(12, .semibold))
            }
            .foregroundStyle(t.text2)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(Capsule().fill(t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage tags")
    }
}

/// Inverted pill so it reads on both themes.
private struct HintToast: View {
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 7) {
            Icon(.copy, size: 12)
            Text("Double-click a clip to copy it").font(Typo.ui(12.5, .semibold))
        }
        .foregroundStyle(t.panel)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(t.text))
        .accessibilityElement(children: .combine)
        .allowsHitTesting(false)
    }
}

private struct ClipRow: View {
    var item: ClipItem
    /// Colour of the clip's tag.
    var color: Color?
    var copied: Bool
    var onTap: () -> Void
    var onCopy: () -> Void
    var onTag: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void
    @Environment(\.tokens) private var t
    private static let maxLines = 3

    var body: some View {
        HStack(spacing: 10) {
            Text(item.text)
                .font(Typo.ui(13))
                .lineSpacing(Typo.lineSpacing(size: 13, lineHeight: 1.4))
                .foregroundStyle(t.text)
                .lineLimit(Self.maxLines)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true) // the row grows with the text, up to `maxLines`
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap) // the store tells a single click (hint) from a double-click (copy)
                .help(item.text)
            if let tag = item.tag { TagChip(tag: tag, custom: color).fixedSize() }
            DockButton(title: copied ? "Copied" : "Copy", glyph: copied ? .check : .copy, iconSize: 12,
                       iconStroke: copied ? 3 : 2.2, metrics: .copy, tone: copied ? .copied : .ctrl, action: onCopy)
            RowIconButton(glyph: .tag, label: item.tag == nil ? "Assign tag" : "Change tag", fg: item.tag == nil ? t.muted : t.accent, action: onTag)
            RowIconButton(glyph: .pin, label: item.pinned ? "Unpin clip" : "Pin clip", fg: item.pinned ? t.accent : t.muted, action: onPin)
            RowIconButton(glyph: .trash, label: "Delete clip", fg: t.red, action: onDelete)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
    }
}
