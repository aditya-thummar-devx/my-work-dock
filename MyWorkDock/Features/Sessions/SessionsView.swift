import SwiftUI
import UniformTypeIdentifiers

/// Sessions board: a column per group plus Ungrouped; drag cards between columns.
struct SessionsScreen: View {
    var model: NotchModel
    @Environment(\.tokens) private var t
    @Environment(\.staticRender) private var staticRender

    var body: some View {
        let store = model.sessions
        VStack(alignment: .leading, spacing: 12) {
            SessionsToolbar(store: store)
            if let m = store.message {
                Text(m.text).font(Typo.ui(11.5)).foregroundStyle(m.error ? t.red : t.muted).padding(.horizontal, 4)
            }
            if !store.loaded {
                ClaudePlaceholder(glyph: .terminal, title: "Loading sessions",
                                  message: "Reading your Claude Code sessions. The first look can take a few seconds.", loading: true)
            } else if store.transcripts.isEmpty {
                ClaudePlaceholder(glyph: .terminal, title: "No sessions yet",
                                  message: "Claude Code sessions from the last 30 days show up here, ready to group and resume.")
            } else if store.searching && store.columns.isEmpty {
                ClaudePlaceholder(glyph: .search, title: "No matching sessions",
                                  message: "Nothing matches “\(store.search.trimmingCharacters(in: .whitespaces))”. Try another word or a wider date range.")
            } else {
                let board = HStack(alignment: .top, spacing: 10) {
                    ForEach(store.columns) { col in BoardColumn(store: store, column: col) }
                    if store.groupFilter == .all && !store.searching { NewGroupColumn(store: store) }
                }
                if staticRender {
                    // Snapshots can't draw a ScrollView's content (see DockScroll).
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .topLeading) { board }
                        .clipped()
                } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { board }
                    .onChange(of: store.focusID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .overlay { if store.choosing != nil { TerminalChooser(store: store) } }
        .task { await store.refresh() }
    }
}

/// First Resume: asks which installed app sessions open in, once.
private struct TerminalChooser: View {
    var store: SessionsStore
    @Environment(\.tokens) private var t

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(t.scrim).onTapGesture(perform: store.cancelChoosing)
            Card(radius: 16, padding: EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open Claude sessions in…").font(Typo.ui(13, .semibold))
                    Text("Apps found on this Mac. Your pick is remembered; change it any time from Open in or Settings › Claude.")
                        .font(Typo.ui(11)).foregroundStyle(t.muted).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 2) {
                        ForEach(store.installedTerminals) { app in
                            Button { Task { await store.choose(app) } } label: {
                                HStack(spacing: 8) {
                                    Icon(.terminal, size: 12).foregroundStyle(t.muted)
                                    Text(app.name).font(Typo.ui(12, .medium))
                                    if let note = app.note { Text(note).font(Typo.ui(10.5)).foregroundStyle(t.faint) }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 8).fill(t.inset))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Spacer()
                        DockButton(title: "Cancel", glyph: nil, metrics: .card, tone: .ctrl, action: store.cancelChoosing)
                    }
                }
            }
            .frame(width: 300)
        }
    }
}

private struct SessionsToolbar: View {
    @Bindable var store: SessionsStore
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Icon(.search, size: 12).foregroundStyle(t.muted)
                DockTextField(text: $store.search, placeholder: "Search sessions…", font: Typo.ui(12))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(t.ctrl))
            .frame(maxWidth: 200)

            MenuChip(label: groupLabel) {
                Button("All groups") { store.groupFilter = .all }
                ForEach(store.groups) { g in Button(g.name) { store.groupFilter = .group(g.id) } }
                Button("Ungrouped") { store.groupFilter = .ungrouped }
            }
            MenuChip(label: store.range.label) {
                ForEach(SessionDateRange.allCases) { r in Button(r.label) { store.range = r } }
            }
            Spacer(minLength: 0)
            DockButton(title: "Auto-group", glyph: .tag, metrics: .card, tone: .ctrl, action: store.autoGroup)
                .help("Put every ungrouped session into a group named after its project")
            MenuChip(label: store.openIn.map { "Open in \($0.name)" } ?? "Pick terminal") {
                ForEach(store.installedTerminals) { app in
                    Button("\(store.openIn == app ? "✓ " : "")\(app.name)\(app.note.map { " — \($0)" } ?? "")") { store.setOpenIn(app) }
                }
            }
            .help("Where Resume opens sessions")
        }
    }

    private var groupLabel: String {
        switch store.groupFilter {
        case .all: "All groups"
        case .ungrouped: "Ungrouped"
        case .group(let id): store.groups.first { $0.id == id }?.name ?? "All groups"
        }
    }
}

/// Small capsule that opens a menu.
private struct MenuChip<Items: View>: View {
    var label: String
    @ViewBuilder var items: Items
    @Environment(\.tokens) private var t

    var body: some View {
        Menu { items } label: {
            HStack(spacing: 4) {
                Text(label).font(Typo.ui(11.5, .semibold)).lineLimit(1)
                Icon(.chevronDown, size: 9)
            }
            .foregroundStyle(t.text2)
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(t.ctrl))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

private struct BoardColumn: View {
    var store: SessionsStore
    var column: SessionsStore.Column
    @Environment(\.staticRender) private var staticRender
    @State private var renaming = false
    @State private var name = ""
    @State private var targeted = false
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if renaming {
                    DockTextField(text: $name, placeholder: column.name, font: Typo.ui(12.5, .semibold), autofocus: true)
                        .onSubmit { store.rename(column.id, name); renaming = false }
                        .onExitCommand { renaming = false }
                } else {
                    Text(column.name).font(Typo.ui(12.5, .semibold)).lineLimit(1)
                        .onTapGesture(count: 2) { if column.isGroup { name = column.name; renaming = true } }
                        .help(column.isGroup ? "Double-click to rename" : "")
                }
                CountBadge(count: column.items.count, on: false)
                Spacer(minLength: 0)
                if column.isGroup {
                    RowIconButton(glyph: .close, label: "Delete group \(column.name)", fg: t.muted, iconSize: 11) { store.delete(column.id) }
                        .help("Delete group (its sessions become ungrouped)")
                }
            }
            .frame(height: 24)
            DockScroll {
                VStack(spacing: 8) {
                    ForEach(column.items) { tx in SessionCard(store: store, transcript: tx).id(tx.id) }
                    if column.items.isEmpty {
                        Text("Drop sessions here").font(Typo.ui(11.5)).foregroundStyle(t.faint)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16).fill(column.isGroup ? t.card : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(targeted ? t.accent : t.line, style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: column.isGroup ? [] : [4, 3])))
        .modifier(DropTarget(enabled: !staticRender) { ids in for id in ids { store.move(id, to: column.id) } } targeted: { targeted = $0 })
    }
}

/// Drag and drop is live-only: snapshots can't render it.
private struct DropTarget: ViewModifier {
    var enabled: Bool
    var onDrop: ([String]) -> Void
    var targeted: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { ids, _ in onDrop(ids); return !ids.isEmpty } isTargeted: { targeted($0) }
        } else {
            content
        }
    }
}

private struct DragSource: ViewModifier {
    var enabled: Bool
    var id: String

    func body(content: Content) -> some View {
        if enabled { content.draggable(id) } else { content }
    }
}

private struct NewGroupColumn: View {
    var store: SessionsStore
    @State private var name = ""
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DockTextField(text: $name, placeholder: "New group…", font: Typo.ui(12.5))
                .onSubmit { store.create(name); name = "" }
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 10).fill(t.inset))
            Text("Press Return to add a column").font(Typo.ui(11)).foregroundStyle(t.faint)
        }
        .padding(10)
        .frame(width: 180, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

private struct SessionCard: View {
    var store: SessionsStore
    var transcript: Transcript
    @Environment(\.staticRender) private var staticRender
    @State private var busy = false
    @Environment(\.tokens) private var t

    var body: some View {
        let tx = transcript
        let focused = store.focusID == tx.id
        VStack(alignment: .leading, spacing: 6) {
            Text(tx.title).font(Typo.ui(12.5, .semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(tx.project).lineLimit(1)
                if let b = tx.branch { Text("⎇ \(b)").lineLimit(1) }
                Text(Self.ago(tx.lastActivity))
            }
            .font(Typo.ui(10.5)).foregroundStyle(t.muted)
            if let pct = tx.contextPercent {
                HStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(t.track)
                            Capsule().fill(pct >= 80 ? t.gaugeRed : pct >= 50 ? t.gaugeAmber : t.gaugeGreen).frame(width: g.size.width * CGFloat(pct) / 100)
                        }
                    }
                    .frame(height: 4)
                    Text("\(pct)%").font(Typo.mono(10)).foregroundStyle(t.muted)
                }
                .help("Context: \(tx.contextTokens ?? 0) of \(tx.contextWindow) tokens")
            }
            HStack(spacing: 6) {
                DockButton(title: "Resume", glyph: .play, iconSize: 9, metrics: .card, tone: .tint, enabled: tx.cwd != nil, busy: busy) {
                    busy = true
                    Task { await store.resume(tx); busy = false }
                }
                if store.installedTerminals.count > 1 {
                    Menu {
                        Section("Open this session in") {
                            ForEach(store.installedTerminals) { app in
                                Button(app.name) { busy = true; Task { await store.resume(tx, in: app); busy = false } }
                            }
                        }
                    } label: {
                        Icon(.chevronDown, size: 9).foregroundStyle(t.text2)
                            .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 8).fill(t.ctrl))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .disabled(tx.cwd == nil)
                    .help("Open with…")
                }
                if let cwd = tx.cwd, let cmd = try? TerminalLauncher.resumeCommand(cwd: cwd, id: tx.id) {
                    DockButton(title: "Copy", glyph: .copy, metrics: .card, tone: .ctrl) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    }
                    .help("Copy the resume command")
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(t.list))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? t.accent : t.listLine, lineWidth: focused ? 1.5 : 1))
        .modifier(DragSource(enabled: !staticRender, id: tx.id))
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86_400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86_400))d ago"
    }
}
