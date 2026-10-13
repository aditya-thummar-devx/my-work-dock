import SwiftUI

extension Geo {
    enum IPChip {
        static let height: CGFloat = 28
        static let minWidth: CGFloat = 132
        static let padLeading: CGFloat = 9
        static let padTrailing: CGFloat = 10
        static let gap: CGFloat = 6
        static let font: CGFloat = 12
        static let icon: CGFloat = 13
        static let checkIcon: CGFloat = 12
        static let spin: Double = 0.7
    }
}

/// Local IP chip in the top row: globe + address; click refreshes, copies and flashes `Copied`.
/// The width never changes between states: the idle label is laid out (hidden) under whichever label shows.
struct LocalIPChip: View {
    var store: LocalIPStore
    @Environment(\.tokens) private var t
    @Environment(\.staticRender) private var staticRender
    @State private var spinning = false

    private var address: String { store.ip ?? "No network" }
    private var disabled: Bool { store.ip == nil }

    var body: some View {
        let copied = store.phase == .copied
        let busy = store.phase == .busy
        let fg = copied ? t.green : disabled ? t.offFg : busy ? t.muted : t.text
        Button(action: { store.click() }) {
            ZStack {
                label(icon: .globe, stroke: 2.1, size: Geo.IPChip.icon, text: address, fg: fg).hidden()
                Group {
                    if copied {
                        label(icon: .check, stroke: 3, size: Geo.IPChip.checkIcon, text: "Copied", fg: fg)
                    } else if busy {
                        label(icon: .refresh, stroke: 2.4, size: Geo.IPChip.icon, text: address, fg: fg, spin: true)
                    } else {
                        label(icon: .globe, stroke: 2.1, size: Geo.IPChip.icon, text: address, fg: fg)
                    }
                }
            }
            .font(Typo.mono(Geo.IPChip.font, .semibold))
            .padding(.leading, Geo.IPChip.padLeading)
            .padding(.trailing, Geo.IPChip.padTrailing)
            .frame(minWidth: Geo.IPChip.minWidth)
            .frame(height: Geo.IPChip.height)
            .background(Capsule().fill(copied ? t.greenBg : disabled ? t.btnOff : t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("Click to refresh + copy")
        .accessibilityLabel(copied ? "Local IP \(address) copied to clipboard" : disabled ? "No network" : "Local IP \(address). Click to refresh and copy")
    }

    /// The globe is `muted` while idle (the text keeps the chip's colour).
    @ViewBuilder
    private func label(icon: Glyph, stroke: CGFloat, size: CGFloat, text: String, fg: Color, spin: Bool = false) -> some View {
        HStack(spacing: Geo.IPChip.gap) {
            Icon(icon, size: size, stroke: stroke)
                .foregroundStyle(icon == .globe && !disabled ? t.muted : fg)
                .rotationEffect(.degrees(spin && spinning ? 360 : 0))
                .onAppear {
                    guard spin, !staticRender else { return }
                    withAnimation(.linear(duration: Geo.IPChip.spin).repeatForever(autoreverses: false)) { spinning = true }
                }
                .onDisappear { spinning = false }
            Text(text).foregroundStyle(fg)
        }
    }
}
