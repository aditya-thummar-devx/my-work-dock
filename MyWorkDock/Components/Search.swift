import SwiftUI

extension Geo {
    enum Search {
        static let height: CGFloat = 32
        static let width: CGFloat = 240
        /// TODO shares its sub-nav row with the tag filter button: with four sub-tabs the full width would truncate their labels.
        static let todoWidth: CGFloat = 190
        static let padLeading: CGFloat = 11
        static let padTrailing: CGFloat = 4
        static let gap: CGFloat = 7
        static let ring: CGFloat = 1.5
        static let icon: CGFloat = 13
        static let font: CGFloat = 12.5
        static let countFont: CGFloat = 11
        static let close: CGFloat = 24
        static let closeIcon: CGFloat = 9
    }

    enum Empty {
        static let radius: CGFloat = 16
        static let dash: [CGFloat] = [3, 3]
        static let titleFont: CGFloat = 18
        static let messageFont: CGFloat = 12.5
        static let gap: CGFloat = 8
        static let buttonTop: CGFloat = 4
        static let buttonHeight: CGFloat = 28
        static let buttonPadX: CGFloat = 12
        static let buttonRadius: CGFloat = 9
        static let buttonFont: CGFloat = 12
    }
}

/// Sub-nav search: a 32 pt circle that opens into a 240 pt field with a result counter and a close button.
/// Shared by Notes › TODO, Prompts and Links. Esc closes it.
struct SearchControl: View {
    var open: Bool
    @Binding var query: String
    var placeholder: String
    /// `3 found`, or empty while nothing is typed.
    var count: String
    /// Width of the open field.
    var width = Geo.Search.width
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        if open {
            HStack(spacing: Geo.Search.gap) {
                Icon(.search, size: Geo.Search.icon, stroke: 2.4)
                DockTextField(text: $query, placeholder: placeholder, font: Typo.ui(Geo.Search.font), autofocus: true)
                    .onKeyPress(.escape) { onClose(); return .handled }
                Text(count).font(Typo.ui(Geo.Search.countFont, .semibold)).foregroundStyle(t.faint).lineLimit(1).fixedSize()
                Button(action: onClose) {
                    Icon(.close, size: Geo.Search.closeIcon, stroke: 3)
                        .foregroundStyle(t.text2)
                        .frame(width: Geo.Search.close, height: Geo.Search.close)
                        .background(Circle().fill(t.btn2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
            .foregroundStyle(t.text2)
            .padding(.leading, Geo.Search.padLeading)
            .padding(.trailing, Geo.Search.padTrailing)
            .frame(width: width, height: Geo.Search.height)
            .background(Capsule().fill(t.ctrl))
            .overlay(Capsule().strokeBorder(t.ink, lineWidth: Geo.Search.ring))
        } else {
            IconButton(glyph: .search, label: placeholder, size: Geo.Search.height, action: onOpen)
        }
    }
}

/// Dashed placeholder that fills the content area when a filter or a search hides everything.
struct EmptyState: View {
    var title = "Nothing here"
    var message: String
    /// Button label; nil hides the button (nothing to clear, the add field is already on screen).
    var action: String?
    var onAction: () -> Void = {}
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(spacing: Geo.Empty.gap) {
            Text(title).font(Typo.display(Geo.Empty.titleFont)).foregroundStyle(t.text)
            Text(message).font(Typo.ui(Geo.Empty.messageFont)).foregroundStyle(t.faint)
            if let action {
                Button(action: onAction) {
                    Text(action)
                        .font(Typo.ui(Geo.Empty.buttonFont, .semibold))
                        .foregroundStyle(t.text)
                        .padding(.horizontal, Geo.Empty.buttonPadX)
                        .frame(height: Geo.Empty.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: Geo.Empty.buttonRadius).fill(t.ctrl))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, Geo.Empty.buttonTop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: Geo.Empty.radius).strokeBorder(t.border, style: StrokeStyle(lineWidth: 1, dash: Geo.Empty.dash)))
    }
}
