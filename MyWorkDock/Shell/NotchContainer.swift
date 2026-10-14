import SwiftUI
import ServiceManagement

extension EnvironmentValues {
    /// False in snapshots: content appears fully faded in (ImageRenderer never runs `.onAppear` animations).
    @Entry var entrance = true
    /// True in snapshots: AppKit-backed controls (TextField) can't be drawn by ImageRenderer, so draw static text.
    @Entry var staticRender = false
    /// Snapshots pin the live-activity bar at a fixed fill.
    @Entry var liveProgress: Double?
}

/// One display's shell: which display it sits on and that display's hardware notch (nil: none).
@MainActor @Observable
final class ShellScreen {
    var id: DisplayID?
    var notch: CGSize?
}

/// Draws the shell for the current mode: silhouette + shadow, mode content clipped to the body.
/// Fills its parent and pins the shell to the top centre, so it works in the real panel and in snapshots.
struct NotchContainer: View {
    var model: NotchModel
    var screen = ShellScreen()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shellCurve = Animation.timingCurve(
        Geo.shellCurve.x1, Geo.shellCurve.y1, Geo.shellCurve.x2, Geo.shellCurve.y2, duration: Geo.shellDuration)
    private static let shellCloseCurve = Animation.timingCurve(
        Geo.shellCloseCurve.x1, Geo.shellCloseCurve.y1, Geo.shellCloseCurve.x2, Geo.shellCloseCurve.y2, duration: Geo.shellCloseDuration)

    var body: some View {
        let mode = model.mode(on: screen.id)
        let g = model.geometry(notch: screen.notch, on: screen.id)
        let t = model.tokens
        let shadowOpacity = mode == .idle ? 0 : (model.isLight ? Geo.shadow.lightOpenOpacity : Geo.shadow.opacity)

        ZStack(alignment: .top) {
            NotchShape(bottomRadius: g.radius, shoulder: g.shoulder)
                .fill(t.panel)
                .shadow(color: .black.opacity(shadowOpacity), radius: Geo.shadow.blur / 2, x: 0, y: Geo.shadow.y)
                .frame(width: g.width, height: g.height)

            content(mode)
                .animation(reduceMotion ? nil : .easeOut(duration: Geo.fadeOut), value: mode)
            .frame(width: g.width, height: g.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: g.radius, bottomTrailingRadius: g.radius))
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(SMAppService.mainApp.status == .enabled ? "✓ Open at login" : "Open at login") {
                if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
            }
            Button("Quit MyWorkDock") { NSApp.terminate(nil) }
            #if DEBUG
            Button(model.bootingOverride == nil ? "Debug: simulate boot" : "Debug: stop boot") {
                model.bootingOverride = model.bootingOverride == nil ? SampleData.bootingSim : nil
            }
            #endif
        }
        .offset(x: g.centerOffset)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : model.shrinking ? Self.shellCloseCurve : Self.shellCurve, value: g)
        .animation(.easeOut(duration: 0.4), value: shadowOpacity)
        .animation(.easeInOut(duration: 0.3), value: model.isLight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.tokens, t)
    }

    /// Incoming content brings its own delayed fade (`Entrance`); outgoing content fades out while the shell moves.
    private static let contentSwap = AnyTransition.asymmetric(insertion: .identity, removal: .opacity)

    @ViewBuilder private func content(_ mode: NotchMode) -> some View {
        switch mode {
        case .idle:
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.openPanel() }
                .accessibilityElement()
                .accessibilityLabel("Open MyWorkDock")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.openPanel() }
                .transition(.identity)
        case .peek:
            Group {
                if model.peekHint {
                    PeekHintView()
                        .accessibilityElement()
                        .accessibilityLabel("Tap to see magic")
                } else {
                    PeekView(data: model.peek, extents: model.peekExtents)
                        .accessibilityElement()
                        .accessibilityLabel("\(model.peek.name), \(model.peek.isPool ? "pool" : "single sign-on"). " + model.peek.bars.map { "\($0.label) \($0.percent.map { "\($0) percent" } ?? "no reading")" }.joined(separator: ", "))
                }
            }
            .onTapGesture { model.openPanel() }
            .accessibilityHint("Opens MyWorkDock")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.openPanel() }
            .modifier(Entrance(timing: Geo.fadePeekLive))
            .transition(Self.contentSwap)
        case .live:
            LiveActivityView(name: model.bootingName ?? "")
                .accessibilityElement()
                .accessibilityLabel("Booting \(model.bootingName ?? "simulator")")
                .modifier(Entrance(timing: Geo.fadePeekLive))
                .transition(Self.contentSwap)
        case .open:
            OpenPanelView(model: model)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("MyWorkDock panel")
                .modifier(Entrance(timing: Geo.fadeOpen))
                .transition(Self.contentSwap)
        }
    }
}

/// Content fades in after the shell moves: opacity 0→1, y −6→0, scale .985→1 (CSS `ease`).
private struct Entrance: ViewModifier {
    var timing: (duration: Double, delay: Double)
    @Environment(\.entrance) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let on = shown || !enabled
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : Geo.fadeOffsetY)
            .scaleEffect(on || reduceMotion ? 1 : Geo.fadeScale)
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: timing.duration).delay(timing.delay), value: on)
            .onAppear { shown = true }
    }
}
