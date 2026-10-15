import SwiftUI

// Composite cards and grouped-list rows built from the primitives. Pure views over plain sample structs,
// so every state is renderable without live data. Actions default to no-ops until the features wire them.

struct Reading: Equatable {
    var percent: Int
    var reset: String
}

struct AccountSample: Identifiable {
    var id: String
    var plan: String
    /// nil = "no reading".
    var session: Reading?
    var week: Reading?
    var active = false
    var name: String { id }
}

struct MemberSample: Identifiable {
    var id: String
    var plan: String
    var net: Double
    /// nil = "no reading".
    var session: Reading?
    var week: Reading?
    var using = false
    var denied = false
    var mine = false
    /// A claudex write on this member is running: the card shows a spinner and its buttons are disabled.
    var busy = false
    var name: String { id }

    var netText: String { Self.netText(net) }

    /// `+1408.1M`, `−6368.1M`; a whole number drops its `.0` (Prototype `fmtNet`).
    static func netText(_ net: Double) -> String {
        (net >= 0 ? "+" : "−") + String(format: "%.1f", abs(net)).replacing(/\.0$/, with: "") + "M"
    }
}

struct DeviceSample: Identifiable {
    var id: String
    var name: String
    var os: String
    var tablet = false
    var status: PillKind
    /// adb serial of a running Android emulator (`emulator-5554`).
    var serial: String?
}

struct TodoSample: Identifiable, Codable {
    var id: Int
    var title: String
    var tag: String
    var due: String
    var hot = false
    var done = false
    /// When the todo was added; nil for seed todos and files written before day sections (they group under "Earlier").
    /// Optional so those files still decode.
    var createdAt: Date?
}

struct WirelessSample: Identifiable {
    var id: String
    var name: String
    var meta: String
    var addr: String
    var status: PillKind
}

extension Geo {
    enum CardMetrics {
        static let memberHeight: CGFloat = 118
        static let deviceHeight: CGFloat = 108
        static let wirelessHeight: CGFloat = 108
        /// Wireless cards share the row with the 220 pt pair card, so they go narrower: 2 columns at medium, 3 at large.
        static let wirelessMinWidth: CGFloat = 230
        static let gridGap: CGFloat = 10
        /// Narrowest an adaptive-grid card gets; medium panel (720 pt content) stays at 2 columns, 3 needs 980 pt.
        static let adaptiveMinWidth: CGFloat = 320
        static let maxColumns = 3
        static let activeBorder: CGFloat = 1.5
    }
}

// MARK: - claudex

/// Usage card: same layout as `MemberCard` (dot, name, plan, thick gauge rows or "no reading"), with Remove / Switch.
/// The active account looks the same with a green border and no (hidden) buttons.
struct AccountCard: View {
    var account: AccountSample
    var onRemove: () -> Void = {}
    var onSwitch: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 16,
             border: account.active ? t.gaugeGreen : nil,
             padding: EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 12)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(account.active ? t.gaugeGreen : t.offFg).frame(width: 7, height: 7)
                    Text(account.name).font(Typo.ui(13.5, .bold))
                    Text(account.plan).font(Typo.ui(11)).foregroundStyle(t.faint)
                    Spacer(minLength: 0)
                    if account.active { Text("ACTIVE").font(Typo.ui(10.5, .bold)).foregroundStyle(t.green) }
                }
                Spacer(minLength: 0)
                if let s = account.session, let w = account.week {
                    GaugeRow(label: "session", percent: s.percent, reset: s.reset, barHeight: Geo.GaugeRow.barPool)
                    Spacer(minLength: 0)
                    GaugeRow(label: "week", percent: w.percent, reset: w.reset, barHeight: Geo.GaugeRow.barPool)
                } else {
                    NoReadingRows()
                }
                Spacer(minLength: 0)
                HStack {
                    DockButton(title: "Remove", glyph: nil, metrics: .card, tone: .outline(t.red), action: onRemove)
                    Spacer(minLength: 0)
                    DockButton(title: "Switch", glyph: nil, metrics: .card, tone: .tint, weight: .bold, action: onSwitch)
                }
                .opacity(account.active ? 0 : 1) // hidden, not removed: the gauges keep the other cards' positions
                .allowsHitTesting(!account.active)
                .accessibilityHidden(account.active)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Geo.CardMetrics.memberHeight)
    }
}

/// Italic `session  no reading` / `week  no reading` rows shown in place of the gauges.
private struct NoReadingRows: View {
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(["session", "week"], id: \.self) { label in
                HStack(spacing: 0) {
                    Text(label).foregroundStyle(t.muted).frame(width: 58, alignment: .leading)
                    Text("no reading").italic()
                }
            }
        }
        .font(Typo.ui(11.5))
        .foregroundStyle(t.faint)
    }
}

/// Pool member card: name, plan, DENIED, net tokens, thick gauges (or "no reading"), Deny / Switch / View details.
struct MemberCard: View {
    var member: MemberSample
    var onDeny: () -> Void = {}
    var onSwitch: () -> Void = {}
    var onDetails: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 16,
             fill: member.using ? t.gaugeGreen.opacity(0.12) : nil,
             border: member.using ? t.gaugeGreen : nil,
             borderWidth: member.using ? Geo.CardMetrics.activeBorder : 1,
             padding: EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 12)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(member.denied ? t.offFg : t.gaugeGreen).frame(width: 7, height: 7)
                    Text(member.name).font(Typo.ui(13.5, .bold))
                    Text(member.plan).font(Typo.ui(11)).foregroundStyle(t.faint)
                    if member.denied { Text("DENIED").font(Typo.ui(10.5, .bold)).foregroundStyle(t.red) }
                    Spacer(minLength: 0)
                    Text(member.netText)
                        .font(Typo.mono(12, .semibold))
                        .foregroundStyle(member.net >= 0 ? t.green : t.red)
                }
                Spacer(minLength: 0)
                if let s = member.session, let w = member.week {
                    GaugeRow(label: "session", percent: s.percent, reset: s.reset, barHeight: Geo.GaugeRow.barPool)
                    Spacer(minLength: 0)
                    GaugeRow(label: "week", percent: w.percent, reset: w.reset, barHeight: Geo.GaugeRow.barPool)
                } else {
                    NoReadingRows()
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if !member.mine {
                        DockButton(title: member.denied ? "Allow" : "Deny", glyph: nil, metrics: .card,
                                   tone: .outline(member.denied ? t.green : nil), enabled: !member.busy, action: onDeny)
                    }
                    Spacer(minLength: 0)
                    if member.busy { Spinner(size: 13).foregroundStyle(t.muted) }
                    if !member.using {
                        DockButton(title: "Switch", glyph: nil, metrics: .card, tone: .tint, weight: .bold, enabled: !member.busy, action: onSwitch)
                    }
                    DockButton(title: "View details", glyph: nil, metrics: .card, tone: .secondary, enabled: !member.busy, action: onDetails)
                }
                .opacity(member.busy ? 0.6 : 1)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Geo.CardMetrics.memberHeight)
    }
}

// MARK: - Emulator

/// Simulator / emulator card: icon tile, name + OS, status pill, Play / Stop / Cold boot. Running gets a green border and glow.
struct DeviceCard: View {
    var device: DeviceSample
    var onPlay: () -> Void = {}
    var onStop: () -> Void = {}
    var onCold: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        let running = device.status == .running
        let live = device.status != .stopped
        Card(radius: 18,
             border: running ? Fixed.runningBorder : nil,
             glow: running ? Fixed.runningGlow : nil,
             padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Icon(device.tablet ? .tablet : .phone, size: 18, stroke: 2)
                        .foregroundStyle(t.text)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(t.btn2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(Typo.ui(14, .semibold)).lineLimit(1)
                        Text(device.os).font(Typo.ui(12)).foregroundStyle(t.faint)
                    }
                    Spacer(minLength: 0)
                    StatusPill(kind: device.status)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    DockButton(title: "Play", glyph: .play, iconSize: 11, metrics: .device,
                               tone: live ? .off : .tint, enabled: !live, action: onPlay)
                    DockButton(title: "Stop", glyph: .stop, iconSize: 10, metrics: .device,
                               tone: running ? .stop : .off, enabled: running, action: onStop)
                    DockButton(title: "Cold boot", glyph: .power, iconSize: 12, iconStroke: 2.4, metrics: .device,
                               tone: device.status == .booting ? .offOnCtrl : .secondary,
                               enabled: device.status != .booting, action: onCold)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Geo.CardMetrics.deviceHeight)
    }
}

/// Wireless device card: wifi tile, name, `OS · UDID / IP`, status pill and a Connect / Disconnect / Retry button.
/// Connected gets the same green border and glow as a running `DeviceCard`.
struct WirelessCard: View {
    var device: WirelessSample
    /// False when there is nothing to do for this device (shown disabled).
    var canAct = true
    var onAction: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        let on = device.status == .connected
        let off = device.status == .unavailable
        Card(radius: 18,
             border: on ? Fixed.runningBorder : nil,
             glow: on ? Fixed.runningGlow : nil,
             padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Icon(.wifi, size: 18, stroke: 2.1)
                        .foregroundStyle(on ? t.green : off ? t.offFg : t.text)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(t.btn2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(Typo.ui(14, .semibold)).lineLimit(1)
                        (Text(device.meta).font(Typo.ui(12)) + Text(" · ").font(Typo.ui(12))
                            + Text(device.addr).font(Typo.mono(11)))
                            .foregroundStyle(t.faint).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    StatusPill(kind: device.status).fixedSize()
                    Spacer(minLength: 0)
                    DockButton(title: on ? "Disconnect" : off ? "Retry" : "Connect", glyph: nil, metrics: .wireless,
                               tone: !canAct ? .off : on ? .secondary : off ? .secondaryQuiet : .tint, enabled: canAct, action: onAction)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: Geo.CardMetrics.wirelessHeight)
    }
}

// MARK: - Grouped list rows

extension Geo {
    enum Row {
        static let todoHeight: CGFloat = 46
        static let snippetHeight: CGFloat = 44
    }
}

/// Todo row: round check, title, tag chip, due text, edit / delete. Done rows are struck through and faint.
/// Editing swaps the title, tag and due for an input with Save and cancel.
struct TodoRow: View {
    var todo: TodoSample
    /// Colour of the todo's tag when the user created it.
    var tagColor: Color?
    var editing = false
    /// Edit-field text; nil draws the title statically (snapshots).
    var editText: Binding<String>?
    /// Tag picked while editing ("" = none), its colour, and the button that opens the tag menu.
    var editTag = ""
    var editTagColor: Color?
    var onEditTag: () -> Void = {}
    var onToggle: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            RoundCheck(done: todo.done, title: todo.title, action: onToggle)
            if editing { editor } else { content }
        }
        .padding(.leading, 12)
        .padding(.trailing, editing ? 10 : 6)
    }

    @ViewBuilder private var editor: some View {
        InlineEditField(text: editText ?? .constant(todo.title), font: Typo.ui(13.5, .medium), onSave: onSave, onCancel: onCancel)
        TagPickerButton(tag: editTag.isEmpty ? nil : editTag, custom: editTagColor, noun: "todo", action: onEditTag)
            .background(GeometryReader { Color.clear.preference(key: EditTagButtonFrameKey.self, value: $0.frame(in: .named(NotesScreen.space))) })
        DockButton(title: "Save", glyph: nil, metrics: .save, tone: .tint, weight: .bold, action: onSave)
        RowIconButton(glyph: .close, label: "Cancel edit", fg: t.text2, fill: t.btn2, iconSize: 11, stroke: 2.8, action: onCancel)
    }

    @ViewBuilder private var content: some View {
        Text(todo.title)
            .font(Typo.ui(13.5, .medium))
            .foregroundStyle(todo.done ? t.faint : t.text)
            .strikethrough(todo.done)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        TagChip(tag: todo.tag, custom: tagColor)
        HStack(spacing: 0) {
            RowIconButton(glyph: .pencil, label: "Edit todo", fg: t.muted, action: onEdit)
            RowIconButton(glyph: .trash, label: "Delete todo", fg: t.red, action: onDelete)
        }
    }
}

/// Where the edited todo's tag button sits in the Notes area, so its menu can open right under it.
struct EditTagButtonFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Single-line inline edit input: inset fill, `ink` ring, takes focus; Enter saves, Esc cancels.
struct InlineEditField: View {
    @Binding var text: String
    var font: Font
    var onSave: () -> Void
    var onCancel: () -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        DockTextField(text: $text, placeholder: "", font: font, autofocus: true)
            .onSubmit(onSave)
            .onKeyPress(.escape) { onCancel(); return .handled }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(t.inset))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(t.ink, lineWidth: 1.5))
    }
}

/// Command / prompt / link row: glyph (`$` / `✦` / `↗`), text, [Open for links,] Copy / edit / delete. Editing swaps in an input with Save and cancel.
/// Commands are one line on a fixed 44 pt row. Prompts keep their line breaks, show at most 3 lines (ellipsis after)
/// and grow, with everything top-aligned.
struct SnippetRow: View {
    var kind: SnippetKind
    var text: String
    var copied = false
    var editing = false
    /// Edit-field text; nil draws `text` statically (snapshots).
    var editText: Binding<String>?
    var onTap: () -> Void = {}
    var onOpen: () -> Void = {}
    var onCopy: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    @Environment(\.tokens) private var t

    private var multiline: Bool { kind == .prompts }

    var body: some View {
        HStack(alignment: multiline ? .top : .center, spacing: 10) {
            Text(kind.glyph).font(Typo.mono(13)).foregroundStyle(t.offFg)
                .frame(height: multiline ? Geo.Prompt.glyphLine : nil)
            if editing { editor } else { content }
        }
        .padding(.leading, multiline ? Geo.Prompt.rowPad.leading : 14)
        .padding(.trailing, multiline ? Geo.Prompt.rowPad.trailing : 6)
        .padding(.vertical, multiline ? Geo.Prompt.rowPad.top : 0)
    }

    @ViewBuilder private var editor: some View {
        if multiline {
            let draft = editText ?? .constant(text)
            DockTextArea(text: draft, placeholder: "", rows: PromptRows.edit(draft.wrappedValue), autofocus: true,
                         onCommit: onSave, onCancel: onCancel)
                .padding(.horizontal, Geo.Prompt.editPad.h + Geo.Prompt.editRing) // the 1.5 pt border adds to the box
                .padding(.vertical, Geo.Prompt.editPad.v + Geo.Prompt.editRing)
                .background(RoundedRectangle(cornerRadius: Geo.Prompt.editRadius).fill(t.inset))
                .overlay(RoundedRectangle(cornerRadius: Geo.Prompt.editRadius).strokeBorder(t.ink, lineWidth: Geo.Prompt.editRing))
        } else {
            InlineEditField(text: editText ?? .constant(text), font: kind.font, onSave: onSave, onCancel: onCancel)
        }
        DockButton(title: "Save", glyph: nil, metrics: .save, tone: .tint, weight: .bold, action: onSave)
        RowIconButton(glyph: .close, label: "Cancel edit", fg: t.text2, fill: t.btn2, iconSize: 11, stroke: 2.8, action: onCancel)
    }

    @ViewBuilder private var content: some View {
        if multiline {
            Text(text)
                .font(kind.font)
                .lineSpacing(Typo.lineSpacing(size: Geo.Prompt.font, lineHeight: Geo.Prompt.lineHeight / Geo.Prompt.font))
                .foregroundStyle(t.text)
                .lineLimit(Geo.Prompt.maxLines)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Geo.Prompt.textTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap) // the store tells a single click (hint) from a double-click (copy)
                .help(text)
        } else {
            Text(text)
                .font(kind.font)
                .foregroundStyle(t.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        }
        if kind == .links {
            DockButton(title: "Open", glyph: .globe, iconSize: 12, metrics: .copy, tone: .ctrl, action: onOpen)
        }
        DockButton(title: copied ? "Copied" : "Copy", glyph: copied ? .check : .copy, iconSize: 12,
                   iconStroke: copied ? 3 : 2.2, metrics: .copy, tone: copied ? .copied : .ctrl, action: onCopy)
        RowIconButton(glyph: .pencil, label: "Edit \(kind.noun)", fg: t.muted, action: onEdit)
        RowIconButton(glyph: .trash, label: "Delete \(kind.noun)", fg: t.red, action: onDelete)
    }
}

/// Grid with fixed-height cards and 10 pt gaps. Two columns, or with `adaptive` as many as fit at `minWidth`, capped at
/// `Geo.CardMetrics.maxColumns` (2 on a medium panel, 3 on a large one, never more however wide the display).
struct CardGrid<Item: Identifiable, Cell: View>: View {
    var items: [Item]
    var adaptive = false
    var minWidth = Geo.CardMetrics.adaptiveMinWidth
    @ViewBuilder var cell: (Item) -> Cell

    var body: some View {
        CardColumns(adaptive: adaptive, minWidth: minWidth) {
            ForEach(items) { cell($0) }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Lays children out in equal-width columns that fill the proposed width. A `Layout` (not `LazyVGrid`) so the column count
/// is known in the same pass as the width, which also holds in `ImageRenderer` snapshots.
private struct CardColumns: Layout {
    var adaptive: Bool
    var minWidth: CGFloat
    private let gap = Geo.CardMetrics.gridGap

    private func columns(for width: CGFloat) -> Int {
        guard adaptive else { return 2 }
        return min(max(Int((width + gap) / (minWidth + gap)), 2), Geo.CardMetrics.maxColumns)
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> (cols: Int, cell: CGFloat, rows: [CGFloat]) {
        let cols = columns(for: width)
        let cell = (width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let rows = stride(from: 0, to: subviews.count, by: cols).map { start in
            subviews[start..<min(start + cols, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
        }
        return (cols, cell, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // A scroll view in a stack can probe with an infinite width; size that like an unspecified one.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minWidth * 2 + gap
        let rows = rowHeights(subviews, width: width).rows
        return CGSize(width: width, height: rows.reduce(0, +) + gap * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (cols, cell, rows) = rowHeights(subviews, width: bounds.width)
        var y = bounds.minY
        for (r, height) in rows.enumerated() {
            for c in 0..<cols where r * cols + c < subviews.count {
                subviews[r * cols + c].place(at: CGPoint(x: bounds.minX + CGFloat(c) * (cell + gap), y: y), anchor: .topLeading,
                                             proposal: ProposedViewSize(width: cell, height: height))
            }
            y += height + gap
        }
    }
}
