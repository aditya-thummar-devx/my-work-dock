import SwiftUI

extension Geo {
    enum SubTab {
        static let spacing: CGFloat = 4
        static let height: CGFloat = 32
        static let pad = (leading: CGFloat(12), trailing: CGFloat(14))
        static let gap: CGFloat = 7
        static let font: CGFloat = 13
        static let icon: CGFloat = 14
        /// Gap between the controls on the right of the sub-nav.
        static let navGap: CGFloat = 6
    }

    enum Segment {
        static let pad: CGFloat = 3
        static let gap: CGFloat = 2
        static let height: CGFloat = 26
        static let padX: CGFloat = 10
        static let itemGap: CGFloat = 6
        static let font: CGFloat = 12.5
        static let countFont: CGFloat = 11
        static let countOpacity = 0.65
        static let lightShadow = (opacity: 0.12, radius: CGFloat(1.5), y: CGFloat(1))
    }
}

struct PillTabItem: Identifiable {
    var id: String
    var label: String
    var glyph: Glyph
}

/// Main tabs: a `ctrl` capsule; the active tab is a tint pill with icon + label, the rest are icon-only.
struct PillTabs: View {
    var items: [PillTabItem]
    var selection: String
    var onSelect: (String) -> Void = { _ in }
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.Chrome.tabsGap) {
            ForEach(items) { item in
                let on = item.id == selection
                Button { onSelect(item.id) } label: {
                    HStack(spacing: Geo.Chrome.tabContentGap) {
                        Icon(item.glyph, size: Geo.Chrome.tabIcon)
                        if on { Text(item.label).font(Typo.ui(13, .semibold)) }
                    }
                    .padding(.leading, on ? Geo.Chrome.tabActivePadding.leading : 0)
                    .padding(.trailing, on ? Geo.Chrome.tabActivePadding.trailing : 0)
                    .frame(minWidth: Geo.Chrome.tabInactiveMinWidth, minHeight: Geo.Chrome.tabHeight)
                    .foregroundStyle(on ? Tokens.onTint : t.muted)
                    .background(Capsule().fill(on ? t.accent : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Geo.Chrome.tabsPadding)
        .background(Capsule().fill(t.ctrl))
    }
}

struct SubTabItem: Identifiable {
    var id: String
    var label: String
    var glyph: Glyph?
    var count: Int?
    /// claudex tab whose output the parsers did not recognise: shows ⚠.
    var warn = false

    init(_ id: String, _ label: String, glyph: Glyph? = nil, count: Int? = nil) {
        self.id = id
        self.label = label
        self.glyph = glyph
        self.count = count
    }
}

/// Sub-nav pills (TODO / Commands / Prompts, Usage / Pool, Devices / Wireless / Tunnel): the active one is a `subOn` pill,
/// with an optional icon and count badge.
struct SubTabs: View {
    var items: [SubTabItem]
    var selection: String
    var onSelect: (String) -> Void = { _ in }
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.SubTab.spacing) {
            ForEach(items) { item in
                let on = item.id == selection
                Button { onSelect(item.id) } label: {
                    HStack(spacing: Geo.SubTab.gap) {
                        if let glyph = item.glyph { Icon(glyph, size: Geo.SubTab.icon) }
                        Text(item.label)
                        if item.warn { Icon(.warning, size: 12, stroke: 2.4).foregroundStyle(t.orange).accessibilityLabel("needs attention") }
                        if let count = item.count { CountBadge(count: count, on: on) }
                    }
                    .font(Typo.ui(Geo.SubTab.font, .semibold))
                    .foregroundStyle(on ? t.text : t.muted)
                    .padding(.leading, Geo.SubTab.pad.leading)
                    .padding(.trailing, Geo.SubTab.pad.trailing)
                    .frame(height: Geo.SubTab.height)
                    .background(Capsule().fill(on ? t.subOn : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct SegmentItem: Identifiable {
    var id: String
    var label: String
    var count: Int
}

/// Android / iOS switch: a `ctrl` capsule with the active segment raised (white in light theme, with a soft shadow).
struct PlatformSegment: View {
    var items: [SegmentItem]
    var selection: String
    var onSelect: (String) -> Void = { _ in }
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.Segment.gap) {
            ForEach(items) { item in
                let on = item.id == selection
                Button { onSelect(item.id) } label: {
                    HStack(spacing: Geo.Segment.itemGap) {
                        Text(item.label)
                        Text("\(item.count)").font(Typo.ui(Geo.Segment.countFont)).opacity(Geo.Segment.countOpacity)
                    }
                    .font(Typo.ui(Geo.Segment.font, .semibold))
                    .foregroundStyle(on ? t.platOnFg : t.muted)
                    .padding(.horizontal, Geo.Segment.padX)
                    .frame(height: Geo.Segment.height)
                    .background {
                        Capsule().fill(on ? t.platOn : .clear)
                            .shadow(color: on && !t.isDark ? .black.opacity(Geo.Segment.lightShadow.opacity) : .clear,
                                    radius: Geo.Segment.lightShadow.radius, y: Geo.Segment.lightShadow.y)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Geo.Segment.pad)
        .background(Capsule().fill(t.ctrl))
    }
}

/// Sub-nav row: sub-tabs on the left, context actions on the right.
struct SubNavRow<Trailing: View>: View {
    var items: [SubTabItem]
    var selection: String
    var onSelect: (String) -> Void = { _ in }
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            SubTabs(items: items, selection: selection, onSelect: onSelect)
            Spacer(minLength: 0)
            HStack(spacing: Geo.SubTab.navGap) { trailing }
        }
        .frame(height: Geo.SubTab.height)
    }
}
