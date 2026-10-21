import SwiftUI

/// Scrim over the whole panel plus the run sheet: the command, the folder, live output and Stop (same frame as claudex's `DetailOverlay`).
struct CommandRunOverlay: View {
    var runner: CommandRunner
    @Environment(\.tokens) private var t

    var body: some View {
        if runner.sheetOpen {
            ZStack(alignment: .top) {
                // The scrim does not close the sheet: a stray click must not stop a running command.
                Scrim().contentShape(Rectangle())
                sheet
                    .padding(.top, 44).padding(.horizontal, 12).padding(.bottom, 12)
            }
            .transition(.opacity)
        }
    }

    private var sheet: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 22)
        return VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                DockScroll {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(runner.output.isEmpty ? "No output yet." : runner.output.text)
                            .font(Typo.mono(12))
                            .foregroundStyle(runner.output.isEmpty ? t.faint : t.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id(Self.bottom)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .onChange(of: runner.output) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { shape.fill(t.pop).shadow(color: t.popShadow, radius: Geo.Chrome.popoverShadow.blur / 2, y: Geo.Chrome.popoverShadow.y) }
        .overlay(shape.strokeBorder(t.border, lineWidth: 1))
        .clipShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command output")
    }

    private static let bottom = "bottom"

    private var header: some View {
        HStack(spacing: 9) {
            Text("$").font(Typo.mono(14)).foregroundStyle(t.ink)
            Text(runner.command).font(Typo.mono(13)).lineLimit(1).truncationMode(.middle)
            statusChip
            Spacer(minLength: 0)
            if runner.isRunning {
                DockButton(title: "Stop", glyph: .stop, iconSize: 11, metrics: .sheet, tone: .stop, action: runner.stop)
            }
            IconButton(glyph: .close, label: runner.isRunning ? "Stop and close" : "Close output", size: 30, iconSize: 11, stroke: 2.8,
                       fill: t.border, fg: t.text, action: runner.dismiss)
        }
        .padding(.leading, 16).padding(.trailing, 10)
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
    }

    @ViewBuilder private var statusChip: some View {
        let (label, fg, bg) = chip
        Text(label).font(Typo.ui(11.5, .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(bg))
    }

    private var chip: (String, Color, Color) {
        switch runner.state {
        case .idle: ("", t.faint, .clear)
        case .running: ("Running", t.text2, t.btn2)
        case .finished(0): ("Finished", t.green, t.greenBg)
        case .finished(let code): ("Exited \(code)", t.red, t.redBg)
        case .stopped: ("Stopped", t.text2, t.btn2)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(runner.folder?.path ?? "").font(Typo.mono(11.5)).foregroundStyle(t.faint).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 0)
            Text("No keyboard input. Use Stop for a command that waits.").font(Typo.ui(11.5)).foregroundStyle(t.faint)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
    }
}
