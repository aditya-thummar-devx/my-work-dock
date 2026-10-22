import SwiftUI

/// claudex: Usage / Pool / Playground / Health, wired to the CLI through `ClaudexStore`.
struct ClaudexScreen: View {
    var model: NotchModel

    var body: some View {
        let store = model.claudex
        content(store)
            .task { await store.refresh() }
    }

    private func content(_ store: ClaudexStore) -> some View {
        VStack(spacing: 0) {
            SubNavRow(items: tabs(store), selection: store.activeTab.rawValue, onSelect: { store.select(ClaudexTab(rawValue: $0) ?? .usage) }) {
                FreshLabel { store.freshLabel }
                PillButton(title: "Refresh", glyph: .refresh, iconSize: 13, action: store.refreshNow)
            }
            .padding(.top, Geo.Chrome.subNavTop)

            if let why = store.unavailable {
                ClaudexMissing(reason: why, loading: store.loading, onRetry: store.retry)
                    .padding(.top, 10)
                Spacer(minLength: 0)
            } else {
                ClaudexToolbar(store: store)
                    .padding(.top, 10)
                    .zIndex(1) // the sort menu hangs below the toolbar, over the content

                Group {
                    switch store.activeTab {
                    case .usage: UsageView(store: store)
                    case .pool: PoolView(store: store)
                    case .play: PlaygroundView(store: store)
                    case .health: HealthView(store: store)
                    }
                }
                .padding(.top, Geo.Chrome.contentTopClaudex)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .overlay {
            if store.sortOpen { Color.clear.contentShape(Rectangle()).onTapGesture { store.sortOpen = false } }
        }
    }

    private func tabs(_ store: ClaudexStore) -> [SubTabItem] {
        let bad = store.unrecognisedTabs
        func item(_ tab: ClaudexTab, _ label: String, count: Int? = nil) -> SubTabItem {
            var i = SubTabItem(tab.rawValue, label, count: count)
            i.warn = bad.contains(tab)
            return i
        }
        return [item(.usage, "Usage", count: store.usage.data?.count ?? 0), item(.pool, "Pool", count: store.members.data?.count ?? 0),
                item(.play, "Playground"), item(.health, "Health")]
    }
}

/// claudex gave nothing (not installed, not runnable, timed out on the first read): the reason and a Retry. The tabs stay empty until it
/// answers.
private struct ClaudexMissing: View {
    var reason: String
    var loading: Bool
    var onRetry: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 10) {
            Icon(.warning, size: 13).foregroundStyle(t.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("claudex is not available. Usage, Pool, Playground and Health need it.")
                    .font(Typo.ui(12.5, .semibold)).foregroundStyle(t.orange).lineLimit(1)
                Text(reason).font(Typo.mono(11)).foregroundStyle(t.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            PillButton(title: loading ? "Checking…" : "Retry", glyph: .refresh, iconSize: 13, action: onRetry)
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(t.inset))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.line, lineWidth: 1))
    }
}

/// "just now" / "42s ago", ticking while the panel is open.
struct FreshLabel: View {
    var text: () -> String
    @Environment(\.tokens) private var t
    @Environment(\.staticRender) private var staticRender

    var body: some View {
        if staticRender {
            label
        } else {
            TimelineView(.periodic(from: .now, by: 5)) { _ in label }
        }
    }

    private var label: some View { Text(text()).font(Typo.ui(12)).foregroundStyle(t.faint) }
}

// MARK: Toolbar

struct ClaudexToolbar: View {
    @Bindable var store: ClaudexStore
    @Environment(\.tokens) private var t

    var body: some View {
        let list = store.tab == .usage || store.tab == .pool
        HStack(spacing: 8) {
            if list {
                HStack(spacing: 6) {
                    ToolButton(padLeading: 8, action: { store.maxOnly.toggle() }) {
                        HStack(spacing: 7) { Checkbox(on: store.maxOnly); Text("5x only") }
                    }
                    .accessibilityAddTraits(store.maxOnly ? .isSelected : [])
                    ToolButton(padLeading: 10, padTrailing: 9, action: { store.sortOpen.toggle() }) {
                        HStack(spacing: 7) {
                            Text("Sort").foregroundStyle(t.faint).fontWeight(.medium)
                            Text(store.sort.label)
                            Icon(.chevronDown, size: 11, stroke: 2.6)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if list {
                    let canMine = store.mineCommand != nil
                    ToolButton(fg: canMine ? t.text : t.offFg, enabled: canMine, action: store.switchToMine) { Text("Switch to mine") }
                }
                DotToolButton(title: store.consuming == true ? "Stop pool" : "Start pool", on: store.consuming == true,
                              enabled: store.consuming != nil) { store.togglePool() }
                DotToolButton(title: store.autoswitchOn == true ? "Disable autoswitch" : "Enable autoswitch", on: store.autoswitchOn == true,
                              enabled: store.autoswitchOn != nil) { store.toggleAutoswitch() }
            }
        }
        .frame(height: Geo.Btn.toolHeight)
        .overlay(alignment: .topLeading) {
            if store.sortOpen && list {
                MenuPopover(options: ClaudexSort.allCases.map(\.label), selected: ClaudexSort.allCases.firstIndex(of: store.sort) ?? 0) { i in
                    store.sort = ClaudexSort.allCases[i]
                    store.sortOpen = false
                }
                .padding(.top, 34).padding(.leading, 90)
            }
        }
    }
}

// MARK: Usage / Pool

/// Shown instead of cards when claudex printed something the parsers do not recognise (or could not run).
struct RawFallback: View {
    var title: String
    var raw: String
    var error: String?
    var loading = false
    @Environment(\.tokens) private var t

    var body: some View {
        if raw.isEmpty && error == nil {
            EmptyHint(text: loading ? "Loading…" : "Nothing loaded yet. Hit Refresh.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Icon(.warning, size: 13).foregroundStyle(t.orange)
                    Text(error ?? "claudex printed something this app does not recognise: \(title)").font(Typo.ui(12, .semibold)).foregroundStyle(t.orange)
                }
                if !raw.isEmpty {
                    DockScroll {
                        Text(ClaudexParsers.lines(raw).joined(separator: "\n"))
                            .font(Typo.mono(11.5)).foregroundStyle(t.text2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(t.inset))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.line, lineWidth: 1))
                }
            }
        }
    }
}

struct UsageView: View {
    var store: ClaudexStore

    var body: some View {
        if store.usage.recognised {
            DockScroll {
                CardGrid(items: store.accountCards, adaptive: true) { a in
                    AccountCard(account: a, onRemove: { store.removeAccount(a.id) }, onSwitch: { store.switchAccount(a.id) })
                }
            }
        } else {
            RawFallback(title: "usage", raw: store.usage.raw, error: store.usage.error, loading: store.loading)
        }
    }
}

struct PoolView: View {
    var store: ClaudexStore

    var body: some View {
        if store.members.recognised {
            DockScroll {
                CardGrid(items: store.memberCards, adaptive: true) { m in
                    MemberCard(member: m, onDeny: { store.toggleAccess(m.id) }, onSwitch: { store.useMember(m.id) }, onDetails: { store.openDetail(m.id) })
                }
            }
        } else {
            RawFallback(title: "pool members", raw: store.members.raw, error: store.members.error, loading: store.loading)
        }
    }
}

// MARK: Playground

struct PlaygroundView: View {
    var store: ClaudexStore
    @Environment(\.tokens) private var t

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - 10
            HStack(spacing: 10) {
                output.frame(width: usable * 1.35 / 2.35)
                commands.frame(width: usable / 2.35)
            }
        }
    }

    private var output: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OUTPUT").font(Typo.ui(11, .bold)).tracking(1).foregroundStyle(t.faint)
                Spacer()
                DockButton(title: "Clear", glyph: nil, metrics: .clear, tone: .ctrl, action: store.clearOutput)
            }
            .padding(.leading, 14).padding(.trailing, 6)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }

            DockScroll {
                VStack(alignment: .leading, spacing: 2) {
                    if store.out.isEmpty {
                        Text("Pick a command on the right. Output shows up here.").font(Typo.ui(12)).foregroundStyle(t.faint)
                    }
                    ForEach(store.out) { line in
                        Text(line.text).font(Typo.mono(12)).foregroundStyle(color(line.kind)).lineLimit(1).fixedSize()
                            .frame(height: 12 * 1.55, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(t.inset))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func color(_ kind: PlayLine.Kind) -> Color {
        switch kind {
        case .cmd: t.ink
        case .ok: t.green
        case .warn: t.orange
        case .text: t.text2
        }
    }

    private var commands: some View {
        DockScroll {
            VStack(spacing: 0) {
                ForEach(store.commands) { k in
                    let open = store.expanded.contains(k.id)
                    VStack(alignment: .leading, spacing: 0) {
                        Button { if let run = k.run { run() } else { store.toggleExpanded(k.id) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if k.expandable {
                                        Icon(.triangle, size: 9).foregroundStyle(t.faint).rotationEffect(.degrees(open ? 90 : 0))
                                    }
                                    Text(k.title).font(Typo.ui(13, .semibold))
                                }
                                Text(k.desc).font(Typo.ui(11.5)).foregroundStyle(t.faint)
                                    .lineSpacing(Typo.lineSpacing(size: 11.5, lineHeight: 1.35))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(t.text)
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(open ? .isSelected : [])
                        if k.expandable && open {
                            FlowLayout(spacing: 5) {
                                ForEach(k.chips) { chip in OptionChip(label: chip.label, danger: chip.danger, action: chip.run) }
                            }
                            .padding(.leading, 22).padding(.trailing, 8).padding(.top, 2).padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(6)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Left-to-right wrapping row (CSS `flex-wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, arrange(bounds.width, subviews).frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), frames)
    }
}

// MARK: Health

struct HealthView: View {
    var store: ClaudexStore
    @Environment(\.tokens) private var t

    var body: some View {
        if store.doctor.recognised {
            let counts = store.healthCounts
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 6) {
                    HealthChip(text: store.consuming == true ? "consuming on" : "consuming off", tone: store.consuming == true ? .on : .off)
                    HealthChip(text: store.poolStatus.data?.sharing.on == true ? "sharing on" : "sharing off",
                               tone: store.poolStatus.data?.sharing.on == true ? .on : .off)
                    HealthChip(text: "\(counts.ok) ok · \(counts.warn) warning(s)", tone: .neutral)
                }
                DockScroll {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(store.healthChecks.enumerated()), id: \.offset) { _, h in
                            HStack(spacing: 8) {
                                Group { if h.ok { Icon(.check, size: 11, stroke: 3.2) } else { Icon(.warning, size: 11, stroke: 2.4) } }
                                    .foregroundStyle(h.ok ? t.green : t.orange)
                                    .frame(width: 12)
                                Text(h.label).fontWeight(.semibold).foregroundStyle(t.text)
                                if !h.detail.isEmpty { Text(h.detail).foregroundStyle(h.ok ? t.faint : t.orange).lineLimit(1) }
                            }
                            .font(Typo.ui(12))
                            .frame(height: 12 * 1.45, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if let note = store.poolStatus.data?.sharing.detail {
                    Text(note.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                        .font(Typo.ui(11.5)).foregroundStyle(t.faint).lineLimit(1)
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16).fill(t.card))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.line, lineWidth: 1))
        } else {
            RawFallback(title: "doctor", raw: store.doctor.raw, error: store.doctor.error, loading: store.loading)
        }
    }
}

// MARK: Member details

/// Scrim over the whole panel plus the details sheet (Prototype: top 44, inset 12, radius 22 / 28).
struct DetailOverlay: View {
    @Bindable var store: ClaudexStore
    @Environment(\.tokens) private var t

    var body: some View {
        if let name = store.detailName {
            ZStack(alignment: .top) {
                Scrim().contentShape(Rectangle()).onTapGesture(perform: store.closeDetail)
                sheet(name)
                    .padding(.top, 44).padding(.horizontal, 12).padding(.bottom, 12)
            }
            .transition(.opacity)
        }
    }

    private func sheet(_ name: String) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 22)
        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Icon(.triangle, size: 11).foregroundStyle(t.text)
                Text(name).font(Typo.ui(16, .bold))
                Text(store.detailMeta).font(Typo.ui(12)).foregroundStyle(t.faint)
                Spacer(minLength: 0)
                IconButton(glyph: .close, label: "Close details", size: 30, iconSize: 11, stroke: 2.8, fill: t.border, fg: t.text, action: store.closeDetail)
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }

            DockScroll { body(store.detail) }

            HStack(spacing: 8) {
                DockButton(title: "Refresh", glyph: .refresh, iconSize: 13,
                           metrics: ButtonMetrics(height: 30, radius: 10, padLeading: 10, padTrailing: 12, font: 12.5),
                           tone: .outline(nil), busy: store.detailLoading, action: store.refreshDetail)
                Button { store.rawOn.toggle() } label: {
                    Text(store.rawOn ? "hide raw" : "show raw").font(Typo.ui(12.5, .semibold))
                        .foregroundStyle(store.rawOn ? t.pop : t.text)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 10).fill(store.rawOn ? t.text : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(t.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(store.rawOn ? .isSelected : [])
                Spacer(minLength: 0)
                Text(store.detailFresh).font(Typo.ui(11.5)).foregroundStyle(t.faint)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { shape.fill(t.pop).shadow(color: t.popShadow, radius: Geo.Chrome.popoverShadow.blur / 2, y: Geo.Chrome.popoverShadow.y) }
        .overlay(shape.strokeBorder(t.border, lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Member details")
    }

    @ViewBuilder private var loadingHint: some View {
        if store.detailLoading {
            HStack(spacing: 8) {
                Spinner(size: 14).foregroundStyle(t.muted)
                Text("Loading…").font(Typo.ui(12.5)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            EmptyHint(text: "Loading…")
        }
    }

    @ViewBuilder private func body(_ capture: Capture<MemberDetail>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.rawOn || !capture.recognised {
                if capture.raw.isEmpty && capture.error == nil {
                    loadingHint
                } else {
                    if !capture.recognised {
                        HStack(spacing: 6) {
                            Icon(.warning, size: 13).foregroundStyle(t.orange)
                            Text(capture.error ?? "claudex printed something this app does not recognise").font(Typo.ui(12, .semibold)).foregroundStyle(t.orange)
                        }
                    }
                    Text(capture.raw.isEmpty ? "" : ClaudexParsers.lines(capture.raw).joined(separator: "\n"))
                        .font(Typo.mono(11.5)).foregroundStyle(t.text2)
                        .lineSpacing(11.5 * 1.5 - 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(t.inset))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(t.line, lineWidth: 1))
                }
            } else if let d = capture.data {
                flowTable(d)
                netLine(d)
                split(d)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flowTable(_ d: MemberDetail) -> some View {
        VStack(spacing: 0) {
            row(spacing: 8) {
                Color.clear.frame(width: 78, height: 1)
                ForEach(["IN", "OUT", "CACHE R", "CACHE W", "REQ"], id: \.self) { h in
                    Text(h).font(Typo.ui(10.5, .bold)).tracking(1).foregroundStyle(t.faint).frame(maxWidth: .infinity, alignment: .trailing)
                }
                Color.clear.frame(width: 104, height: 1)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }

            ForEach(Array(d.flows.enumerated()), id: \.offset) { i, f in
                row(spacing: 8) {
                    Text(f.label).font(Typo.ui(13, .semibold)).frame(width: 78, alignment: .leading)
                    ForEach([f.in, f.out, f.cacheRead, f.cacheWrite, f.req], id: \.self) { v in
                        Text(v).font(Typo.mono(12.5)).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Text(f.note).font(Typo.ui(11.5)).foregroundStyle(t.faint).padding(.leading, 6).frame(width: 104, alignment: .leading)
                }
                .frame(height: 30)
                .overlay(alignment: .bottom) { if i < d.flows.count - 1 { Rectangle().fill(t.line).frame(height: 1) } }
            }
        }
    }

    private func row<C: View>(spacing: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: spacing, content: content)
    }

    @ViewBuilder private func netLine(_ d: MemberDetail) -> some View {
        if let net = d.netM {
            let give = d.netDir == "giver" || (d.netDir == nil && net >= 0)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("net give/take").foregroundStyle(t.muted)
                Text(MemberSample.netText(net)).font(Typo.mono(12.5, .bold)).foregroundStyle(give ? t.green : t.red)
                RoleChip(text: d.netDir ?? (give ? "giver" : "taker"), color: give ? t.green : t.red)
            }
            .font(Typo.ui(12.5))
        }
    }

    private func split(_ d: MemberDetail) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            (Text("USAGE SPLIT").tracking(1) + Text(d.splitNote.map { "  ·  \($0)" } ?? "").tracking(0).fontWeight(.medium))
                .font(Typo.ui(10.5, .bold)).foregroundStyle(t.faint)
            ForEach(Array(d.windows.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading, spacing: 3) {
                    splitRow(label: w.label, pct: w.pct, color: w.pct.map(t.gaugeColor) ?? t.gaugeGreen, labelColor: t.muted,
                             sub: w.resets.map { "resets \($0)" } ?? (w.pct == nil ? "no reading" : ""))
                    if w.drivers.isEmpty, let note = w.note { Text(note).font(Typo.ui(11.5)).foregroundStyle(t.faint) }
                    ForEach(Array(w.drivers.enumerated()), id: \.offset) { _, dr in
                        splitRow(label: dr.name + (dr.you ? " (you)" : ""), pct: dr.pct, color: t.gaugeGreen, labelColor: t.text, sub: dr.tokens)
                    }
                }
            }
            Text(d.footnote ?? "shares are of observed proxy tokens, approximate")
                .font(Typo.ui(11)).foregroundStyle(t.faint).padding(.top, 2)
        }
    }

    private func splitRow(label: String, pct: Int?, color: Color, labelColor: Color, sub: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Typo.ui(12.5)).foregroundStyle(labelColor).lineLimit(1).frame(width: 150, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.track)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(pct ?? 0, 0), 100)) / 100)
                }
            }
            .frame(height: Geo.GaugeRow.barSplit)
            Text(pct.map { "\($0)%" } ?? "—").font(Typo.mono(12, .bold)).frame(width: 42, alignment: .trailing)
            Text(sub).font(Typo.ui(11.5)).foregroundStyle(t.faint).lineLimit(1).frame(width: 130, alignment: .leading)
        }
    }
}
