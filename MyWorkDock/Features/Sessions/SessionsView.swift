import SwiftUI
import UniformTypeIdentifiers

/// Sessions board: a column per group plus Ungrouped; drag cards between columns.
struct SessionsScreen: View {
    var model: NotchModel
    @Environment(\.tokens) private var t

    var body: some View {
        let store = model.sessions
        VStack(alignment: .leading, spacing: 10) {
            SessionsToolbar(store: store).padding(.top, Geo.Chrome.subNavTop)
            if let m = store.message {
                Text(m.text).font(Typo.ui(11.5)).foregroundStyle(m.error ? t.red : t.muted).padding(.horizontal, 4)
            }
            if store.transcripts.isEmpty {
                EmptyHint(text: store.loading ? "Reading your Claude Code sessions…" : "No Claude Code sessions in the last 30 days.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(store.columns) { col in BoardColumn(store: store, column: col) }
                            if store.groupFilter == .all { NewGroupColumn(store: store) }
                        }
                    }
                    .onChange(of: store.focusID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task { await store.refresh() }
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
            MenuChip(label: "Open in \(store.openIn.name)") {
                ForEach(store.installedTerminals) { app in
                    Button("\(app.name)\(app.realPrompts ? "" : " — messages as notes")") { store.setOpenIn(app) }
                }
            }
            IconButton(glyph: .refresh, label: "Refresh", size: 28) { Task { await store.refresh() } }
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
            ScrollView(.vertical, showsIndicators: false) {
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
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { store.move(id, to: column.id) }
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
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
        .draggable(tx.id)
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86_400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86_400))d ago"
    }
}
