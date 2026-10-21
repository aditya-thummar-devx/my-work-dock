import SwiftUI

extension Geo {
    enum Sheet {
        static let padding: CGFloat = 14
        static let radius: CGFloat = 18
        static let gap: CGFloat = 12
        static let iconTile: CGFloat = 34
        static let iconTileRadius: CGFloat = 11
        static let iconSize: CGFloat = 16
        static let textGap: CGFloat = 3
        static let titleFont: CGFloat = 13.5
        static let commandFont: CGFloat = 12
        static let noteFont: CGFloat = 11.5
        static let hintFont: CGFloat = 11
        static let hintOpacity = 0.6
        /// Distance from the panel's left / right / bottom edge.
        static let insetX: CGFloat = 20
        static let bottom: CGFloat = 54
        static let shadow = (radius: CGFloat(30), y: CGFloat(24))
    }
}

/// Every state-changing command asks here first and shows the exact command string.
/// Destructive variants (Remove, Deny) use a red icon, a red note and a `#E5484D` confirm button.
struct ConfirmSheet: View {
    var title: String
    var command: String
    var note: String
    var confirmTitle: String
    var danger = false
    var commandLines = 1
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: Geo.Sheet.gap) {
            Icon(.warning, size: Geo.Sheet.iconSize)
                .foregroundStyle(danger ? t.red : t.text)
                .frame(width: Geo.Sheet.iconTile, height: Geo.Sheet.iconTile)
                .background(RoundedRectangle(cornerRadius: Geo.Sheet.iconTileRadius).fill(danger ? t.redBg : t.grayBg))

            VStack(alignment: .leading, spacing: Geo.Sheet.textGap) {
                Text(title).font(Typo.ui(Geo.Sheet.titleFont, .semibold))
                Text("$ \(command)")
                    .font(Typo.mono(Geo.Sheet.commandFont))
                    .foregroundStyle(t.text2)
                    .lineLimit(commandLines)
                    .truncationMode(.tail)
                Text(note).font(Typo.ui(Geo.Sheet.noteFont)).foregroundStyle(danger ? t.red : t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sheetButton(title: "Cancel", hint: "esc", fill: t.btn2, fg: t.text, weight: .semibold, shortcut: .cancelAction, action: onCancel)
            sheetButton(title: confirmTitle, hint: "↵", fill: danger ? Fixed.danger : t.accent,
                        fg: danger ? Fixed.onDanger : Tokens.onTint, weight: .bold, shortcut: .defaultAction, action: onConfirm)
        }
        .padding(Geo.Sheet.padding + 1)
        .background {
            RoundedRectangle(cornerRadius: Geo.Sheet.radius).fill(t.pop)
                .shadow(color: t.popShadow, radius: Geo.Sheet.shadow.radius, y: Geo.Sheet.shadow.y)
        }
        .overlay(RoundedRectangle(cornerRadius: Geo.Sheet.radius).strokeBorder(t.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm action")
    }

    private func sheetButton(title: String, hint: String, fill: Color, fg: Color, weight: Font.Weight,
                             shortcut: KeyboardShortcut, action: @escaping () -> Void) -> some View {
        let m = ButtonMetrics.confirm
        return Button(action: action) {
            (Text("\(title) ").font(Typo.ui(m.font, weight))
                + Text(hint).font(Typo.mono(Geo.Sheet.hintFont)).foregroundColor(fg.opacity(Geo.Sheet.hintOpacity)))
                .foregroundStyle(fg)
                .padding(.horizontal, m.padLeading)
                .frame(height: m.height)
                .background(RoundedRectangle(cornerRadius: m.radius).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
    }
}
