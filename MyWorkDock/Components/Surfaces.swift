import SwiftUI

extension Geo {
    enum Surface {
        static let listRadius: CGFloat = 16
        static let fieldHeight: CGFloat = 44
        static let fieldRadius: CGFloat = 14
        static let fieldGap: CGFloat = 10
        static let glowSpread: CGFloat = 4
        /// Open-panel bottom radius, used by the scrim and the details sheet.
        static let scrimRadius: CGFloat = 36
    }
}

/// Rounded surface with an inside border (the designs use `box-sizing: border-box`, so the border eats into the frame).
/// `glow` adds the 4 pt spread ring of a running device card.
struct Card<Content: View>: View {
    var radius: CGFloat = Geo.Surface.listRadius
    var fill: Color?
    var border: Color?
    var borderWidth: CGFloat = 1
    var glow: Color?
    var padding = EdgeInsets()
    @ViewBuilder var content: Content
    @Environment(\.tokens) private var t

    var body: some View {
        content
            .padding(padding)
            .padding(borderWidth)
            .background {
                RoundedRectangle(cornerRadius: radius).fill(fill ?? t.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(border ?? t.line, lineWidth: borderWidth)
            }
            .background {
                if let glow {
                    RoundedRectangle(cornerRadius: radius + Geo.Surface.glowSpread)
                        .fill(glow)
                        .padding(-Geo.Surface.glowSpread)
                }
            }
    }
}

/// Grouped list: a `list` fill with a hairline border, fixed-height rows, 1 pt dividers between rows.
/// Rows are built by the caller (index-based) and are centred in the row height.
struct GroupedList<Row: View>: View {
    var count: Int
    var rowHeight: CGFloat
    /// Total height cap (list border included): rows beyond it are clipped, as in the scrolling screens.
    var maxHeight: CGFloat?
    /// Rows scroll inside the fixed rounded surface when they don't fit the proposed height (`overflow-y: auto`).
    var scrolls = false
    /// Rows grow with their content (`rowHeight` is the minimum), like the prompt rows.
    var autoHeight = false
    @ViewBuilder var row: (Int) -> Row
    @Environment(\.tokens) private var t

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                sized(row(i).padding(.top, i > 0 ? 1 : 0)) // the divider takes 1 pt of the row's own height
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(t.line).frame(height: 1) }
                    }
            }
        }
        .frame(maxWidth: .infinity) // an empty list still spans the width (its border and fill show)
    }

    @ViewBuilder private func sized<V: View>(_ v: V) -> some View {
        if autoHeight { v.frame(minHeight: rowHeight) } else { v.frame(height: rowHeight) }
    }

    private func surface<C: View>(_ inner: C) -> some View {
        inner
            .clipped()
            .padding(1)
            .background(RoundedRectangle(cornerRadius: Geo.Surface.listRadius).fill(t.list))
            .overlay(RoundedRectangle(cornerRadius: Geo.Surface.listRadius).strokeBorder(t.listLine, lineWidth: 1))
    }

    var body: some View {
        if scrolls && autoHeight {
            // Row heights depend on the width (wrapped text): lay the rows out at the real width, then use the plain
            // list while it fits and the same rows in a scroller that fills the space when it doesn't.
            GeometryReader { geo in
                // `fixedSize`: rows keep their content height instead of being squeezed into the visible height.
                let tall = rows.frame(width: geo.size.width - 2).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .vertical) {
                    surface(tall)
                    surface(DockScroll { tall }.frame(maxHeight: .infinity, alignment: .top))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        } else if scrolls {
            // Rows are a known height, so the surface is `min(rows, available)` and the rows scroll inside it.
            GeometryReader { geo in
                surface(DockScroll { rows }.frame(height: max(0, min(CGFloat(count) * rowHeight, geo.size.height - 2)), alignment: .top))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        } else {
            surface(rows.frame(maxHeight: maxHeight.map { $0 - 2 }, alignment: .top))
        }
    }
}

/// Vertical scroller for screens whose content can outgrow the panel. `ScrollView` is AppKit-backed and
/// ImageRenderer can't draw it, so snapshots get the content clipped to the same frame.
struct DockScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.staticRender) private var staticRender

    var body: some View {
        if staticRender {
            // Takes the proposed size and clips taller content to it (a flexible `frame` would grow to fit it instead).
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { content }
                .clipped()
        } else {
            ScrollView(showsIndicators: false) { content }
        }
    }
}

/// Single-line text input. `TextField` is AppKit-backed and ImageRenderer can't draw it, so snapshots get static text.
struct DockTextField: View {
    @Binding var text: String
    var placeholder: String
    var font: Font
    var alignment: Alignment = .leading
    var tracking: CGFloat = 0
    /// Takes keyboard focus when it appears (inline edit fields).
    var autofocus = false
    @Environment(\.tokens) private var t
    @Environment(\.staticRender) private var staticRender
    @FocusState private var focused: Bool

    var body: some View {
        if staticRender {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(text.isEmpty ? Fixed.placeholder : t.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Fixed.placeholder))
                .textFieldStyle(.plain)
                .font(font)
                .tracking(tracking)
                .foregroundStyle(t.text)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .focused($focused)
                .task { if autofocus { focused = true } }
        }
    }
}

/// Quick-add bar (todo, command): 44 pt, `card` fill, 1 pt `border`, leading glyph / prompt, input, trailing button.
struct FieldBar<Leading: View, Trailing: View>: View {
    @Binding var text: String
    var placeholder: String
    var font: Font
    var padLeading: CGFloat
    var padTrailing: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.Surface.fieldGap) {
            leading
            DockTextField(text: $text, placeholder: placeholder, font: font)
            trailing
        }
        .padding(.leading, padLeading + 1)
        .padding(.trailing, padTrailing + 1)
        .frame(height: Geo.Surface.fieldHeight)
        .background(RoundedRectangle(cornerRadius: Geo.Surface.fieldRadius).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: Geo.Surface.fieldRadius).strokeBorder(t.border, lineWidth: 1))
    }
}

/// Dim layer behind sheets, clipped to the open panel's rounded bottom.
struct Scrim: View {
    @Environment(\.tokens) private var t

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: Geo.Surface.scrimRadius, bottomTrailingRadius: Geo.Surface.scrimRadius)
            .fill(t.scrim)
    }
}
