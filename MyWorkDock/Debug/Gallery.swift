import SwiftUI

/// Every component on one sheet, for side-by-side review in both themes (`gallery-dark`, `gallery-light`).
/// Mirrors the designs' sample data; there is no reference PNG, so nothing here is compared pixel for pixel.
struct Gallery: View {
    static let height: CGFloat = 2530
    private static let columnWidth: CGFloat = 472

    @Environment(\.tokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 22) { leftColumn }.frame(width: Self.columnWidth)
            VStack(alignment: .leading, spacing: 22) { rightColumn }.frame(width: Self.columnWidth)
        }
        .padding(24)
        .frame(width: 1040, height: Self.height, alignment: .topLeading)
        .background(t.panel)
        .foregroundStyle(t.text)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Typo.ui(10.5, .bold)).tracking(1).foregroundStyle(t.faint)
            content()
        }
    }

    // MARK: Left column: controls, chips, gauges

    @ViewBuilder private var leftColumn: some View {
        section("PillTabs") {
            PillTabs(items: MainTab.allCases.map { PillTabItem(id: $0.rawValue, label: $0.label, glyph: $0.glyph) }, selection: "notes")
            PillTabs(items: MainTab.allCases.map { PillTabItem(id: $0.rawValue, label: $0.label, glyph: $0.glyph) }, selection: "claudex")
        }
        section("SubTabs · PlatformSegment") {
            SubTabs(items: SubNav.notes, selection: "todo")
            SubTabs(items: SubNav.claudex, selection: "pool")
            SubTabs(items: SubNav.emulator, selection: "wireless")
            PlatformSegment(items: [SegmentItem(id: "android", label: "Android", count: 2), SegmentItem(id: "ios", label: "iOS", count: 4)], selection: "ios")
        }
        section("IconButton · PillButton") {
            HStack(spacing: 6) {
                IconButton(glyph: .search, label: "Search", size: 32)
                IconButton(glyph: .refresh, label: "Refresh", size: 32)
                IconButton(glyph: .pin, label: "Pin")
                IconButton(glyph: .pin, label: "Pinned", fill: t.accent, fg: Tokens.onTint)
                IconButton(glyph: .gear, label: "Settings", fill: t.text, fg: t.panel)
                IconButton(glyph: .close, label: "Close", size: 28, iconSize: 11, stroke: 2.8)
                PillButton(title: "Refresh", glyph: .refresh, iconSize: 13)
            }
            HStack(spacing: 6) {
                RowIconButton(glyph: .pencil, label: "Edit", fg: t.muted)
                RowIconButton(glyph: .trash, label: "Delete", fg: t.red)
                RowIconButton(glyph: .close, label: "Cancel", fg: t.text2, fill: t.btn2, iconSize: 11, stroke: 2.8)
            }
        }
        section("ToolButton") {
            HStack(spacing: 6) {
                ToolButton(padLeading: 8) { HStack(spacing: 7) { Checkbox(on: false); Text("5x only") } }
                ToolButton(padLeading: 8) { HStack(spacing: 7) { Checkbox(on: true); Text("5x only") } }
                ToolButton(padLeading: 10, padTrailing: 9) {
                    HStack(spacing: 7) { Text("Sort").foregroundStyle(t.faint).fontWeight(.medium); Text("Expiring soon"); Icon(.chevronDown, size: 11, stroke: 2.6) }
                }
            }
            HStack(spacing: 6) {
                ToolButton(fg: t.offFg, enabled: false) { Text("Switch to mine") }
                DotToolButton(title: "Start pool", on: false)
                DotToolButton(title: "Stop pool", on: true)
            }
        }
        section("DockButton") {
            HStack(spacing: 6) {
                DockButton(title: "Switch", glyph: nil, metrics: .card, tone: .tint, weight: .bold)
                DockButton(title: "Remove", glyph: nil, metrics: .card, tone: .outline(t.red))
                DockButton(title: "Deny", glyph: nil, metrics: .card, tone: .outline(nil))
                DockButton(title: "View details", glyph: nil, metrics: .card, tone: .secondary)
            }
            HStack(spacing: 6) {
                DockButton(title: "Play", glyph: .play, iconSize: 11, metrics: .device, tone: .tint)
                DockButton(title: "Stop", glyph: .stop, iconSize: 10, metrics: .device, tone: .stop)
                DockButton(title: "Cold boot", glyph: .power, iconSize: 12, iconStroke: 2.4, metrics: .device, tone: .secondary)
                DockButton(title: "Play", glyph: .play, iconSize: 11, metrics: .device, tone: .off, enabled: false)
            }
            HStack(spacing: 6) {
                DockButton(title: "Add", glyph: nil, metrics: .add, tone: .tint, weight: .bold)
                DockButton(title: "Copy", glyph: .copy, metrics: .copy, tone: .ctrl)
                DockButton(title: "Copied", glyph: .check, iconStroke: 3, metrics: .copy, tone: .copied)
                DockButton(title: "Remove", glyph: nil, metrics: .confirm, tone: .danger, weight: .bold)
            }
            HStack(spacing: 6) {
                DockButton(title: "Retry", glyph: nil, metrics: .wireless, tone: .secondaryQuiet)
                DockButton(title: "Connect", glyph: nil, metrics: .wireless, tone: .tint)
                DockButton(title: "Disconnect", glyph: nil, metrics: .wireless, tone: .secondary)
            }
            DockButton(title: "Run reverse tunnel", glyph: .play, iconSize: 12, metrics: .run, tone: .tint, weight: .bold)
        }
        section("Chips") {
            HStack(spacing: 6) { ForEach(["release", "bug", "deps", "docs", "idea", "client", "misc"], id: \.self) { TagChip(tag: $0) } }
            HStack(spacing: 6) {
                PresetChip(label: "Metro", port: "8081", on: true)
                PresetChip(label: "API", port: "3000", on: false)
                CountBadge(count: 3, on: true)
                CountBadge(count: 11, on: false)
                RoleChip(text: "giver", color: t.green)
                RoleChip(text: "taker", color: t.red)
            }
            HStack(spacing: 6) {
                HealthChip(text: "sharing on", tone: .on)
                HealthChip(text: "consuming off", tone: .off)
                HealthChip(text: "12 ok · 2 warning(s)", tone: .neutral)
            }
            HStack(spacing: 6) {
                OptionChip(label: "status")
                OptionChip(label: "stop", danger: true)
                Checkbox(on: false)
                Checkbox(on: true)
                RoundCheck(done: false)
                RoundCheck(done: true)
            }
        }
        section("StatusPill") {
            HStack(spacing: 6) { StatusPill(kind: .running); StatusPill(kind: .booting); StatusPill(kind: .stopped) }
            HStack(spacing: 6) { StatusPill(kind: .connected); StatusPill(kind: .disconnected); StatusPill(kind: .unavailable) }
        }
        section("BarGauge · GaugeRow") {
            VStack(spacing: 6) {
                ForEach([0, 38, 72, 100], id: \.self) { BarGauge(percent: $0) }
                BarGauge(percent: 56, height: Geo.GaugeRow.barPool)
                BarGauge(percent: 84, height: Geo.GaugeRow.barSplit)
            }
            GaugeRow(label: "session", percent: 20, reset: "2:39pm")
            GaugeRow(label: "week", percent: 80, reset: "Oct 15 11:29am", barHeight: Geo.GaugeRow.barPool)
        }
        section("RingGauge (on black)") {
            HStack(spacing: 14) {
                ForEach([0, 25, 56, 90], id: \.self) { RingGauge(percent: $0).foregroundStyle(Fixed.peekText) }
                RingGauge(percent: nil).foregroundStyle(Fixed.peekText)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
        }
    }

    // MARK: Right column: cards, lists, sheets

    @ViewBuilder private var rightColumn: some View {
        section("AccountCard") {
            AccountCard(account: SampleData.accounts[0])
            AccountCard(account: SampleData.accounts[1])
        }
        section("MemberCard") {
            MemberCard(member: SampleData.members[0])
            MemberCard(member: SampleData.deniedMember)
            MemberCard(member: SampleData.noReadingMember)
            MemberCard(member: { var m = SampleData.members[2]; m.using = true; return m }())
        }
        section("DeviceCard") {
            DeviceCard(device: SampleData.iosDevices[0])
            DeviceCard(device: SampleData.iosDevices[2])
            DeviceCard(device: SampleData.iosDevicesBooting[1])
        }
        section("WirelessCard") {
            WirelessCard(device: SampleData.wirelessIOS[0])
            WirelessCard(device: SampleData.wirelessIOS[3])
        }
        section("GroupedList · rows") {
            GroupedList(count: 3, rowHeight: Geo.Row.todoHeight) { TodoRow(todo: SampleData.todos[[0, 3, 4][$0]]) }
            GroupedList(count: 3, rowHeight: Geo.Row.snippetHeight) { i in
                SnippetRow(kind: .commands, text: SampleData.commands[i], copied: i == 1, editing: i == 2)
            }
            GroupedList(count: 2, rowHeight: Geo.Row.snippetHeight) { i in
                SnippetRow(kind: .prompts, text: SampleData.prompts[i + 2], copied: i == 1, editing: false)
            }
        }
        section("ConfirmSheet") {
            ConfirmSheet(title: "Switch this Mac to studio?", command: "claudex switch studio --force",
                         note: "Sessions started after this use it.", confirmTitle: "Switch")
            ConfirmSheet(title: "Remove studio?", command: "claudex remove studio --force",
                         note: "Permanently deletes the saved token. Cannot be undone.", confirmTitle: "Remove", danger: true)
        }
        section("Settings screen · Menu popover") {
            HStack(alignment: .top, spacing: 16) {
                SettingsScreen(theme: t.isDark ? .dark : .light, tint: t.tint).frame(width: 500, height: 371) // what the gallery leaves beside the menu
                MenuPopover(options: Array(SampleData.sortOptions.prefix(4)), selected: 1)
            }
        }
    }
}
