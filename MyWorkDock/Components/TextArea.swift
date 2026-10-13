import SwiftUI
import AppKit

extension Geo {
    enum Prompt {
        /// `line-height: 19px` in the add field, the edit field and the rows.
        static let lineHeight: CGFloat = 19
        static let font: CGFloat = 13
        static let rowPad = EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 6)
        /// `padding-top` of the row text (the 30 pt buttons are centred on the first line this way).
        static let textTop: CGFloat = 5
        static let glyphLine: CGFloat = 30
        static let maxLines = 3
        static let addPad = EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 6)
        static let metaFont: CGFloat = 11
        static let metaGap: CGFloat = 8
        static let editPad = (v: CGFloat(6), h: CGFloat(10))
        static let editRadius: CGFloat = 9
        static let editRing: CGFloat = 1.5
    }
}

/// Visible rows of the prompt fields (Prototype `promptRows`, `editRows`).
enum PromptRows {
    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// Add field: one row per line, 2…5, then it scrolls.
    static func add(_ text: String) -> Int { min(5, max(2, lineCount(text))) }

    /// Inline edit: one row per line or per ~70 characters, 2…6.
    static func edit(_ text: String) -> Int { min(6, max(2, lineCount(text), Int((Double(text.count) / 70).rounded(.up)))) }

    /// `3 lines`, empty while the text is a single line.
    static func meta(_ text: String) -> String { text.contains("\n") ? "\(lineCount(text)) lines" : "" }
}

/// Multi-line input for prompts: ↵ commits, ⇧↵ inserts a newline, Esc cancels (when `onCancel` is set).
/// `rows` × 19 pt tall; longer text scrolls. `NSTextView` is AppKit-backed and ImageRenderer can't draw it,
/// so snapshots get the text as a static clamp.
struct DockTextArea: View {
    @Binding var text: String
    var placeholder: String
    var rows: Int
    var autofocus = false
    var onCommit: () -> Void = {}
    var onCancel: (() -> Void)?
    @Environment(\.tokens) private var t
    @Environment(\.staticRender) private var staticRender

    var body: some View {
        Group {
            if staticRender {
                Text(text.isEmpty ? placeholder : text)
                    .font(Typo.ui(Geo.Prompt.font))
                    .lineSpacing(Typo.lineSpacing(size: Geo.Prompt.font, lineHeight: Geo.Prompt.lineHeight / Geo.Prompt.font))
                    .foregroundStyle(text.isEmpty ? Fixed.placeholder : t.text)
                    .lineLimit(rows)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ZStack(alignment: .topLeading) {
                    TextAreaRepresentable(text: $text, color: NSColor(t.text), autofocus: autofocus, onCommit: onCommit, onCancel: onCancel)
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Typo.ui(Geo.Prompt.font))
                            .foregroundStyle(Fixed.placeholder)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .frame(height: CGFloat(rows) * Geo.Prompt.lineHeight)
    }
}

struct TextAreaRepresentable: NSViewRepresentable {
    @Binding var text: String
    var color: NSColor
    var autofocus: Bool
    var onCommit: () -> Void
    var onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let view = NSTextView()
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.string = text
        Self.style(view, color: color)
        scroll.documentView = view
        if autofocus { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            Self.style(view, color: color)
        }
        if view.textColor != color { Self.style(view, color: color) }
    }

    /// 13 pt text on 19 pt lines: the extra leading is split above and below, like CSS half-leading.
    static func style(_ view: NSTextView, color: NSColor) {
        let font = NSFont.systemFont(ofSize: Geo.Prompt.font)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Geo.Prompt.lineHeight
        paragraph.maximumLineHeight = Geo.Prompt.lineHeight
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            .baselineOffset: (Geo.Prompt.lineHeight - natural) / 2,
        ]
        view.font = font
        view.textColor = color
        view.insertionPointColor = color
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = attributes
        view.textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: view.textStorage?.length ?? 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextAreaRepresentable
        init(_ parent: TextAreaRepresentable) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    view.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onCommit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard let cancel = parent.onCancel else { return false }
                cancel()
                return true
            default:
                return false
            }
        }
    }
}
