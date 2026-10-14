import AppKit
import SwiftUI

/// Settings › Mascot, persisted in UserDefaults.
@MainActor @Observable
final class MascotSettings {
    private(set) var enabled: Bool
    private(set) var kind: MascotKind
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        enabled = defaults?.bool(forKey: "mascotEnabled") ?? false
        kind = defaults?.string(forKey: "mascotKind").flatMap(MascotKind.init(rawValue:)) ?? .kunoichi
    }

    func setEnabled(_ on: Bool) { enabled = on; defaults?.set(on, forKey: "mascotEnabled") }
    func setKind(_ k: MascotKind) { kind = k; defaults?.set(k.rawValue, forKey: "mascotKind") }
}

/// Accepts key focus (for a question's "Other…" field) without activating the app.
private final class MascotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The character on the Dock's Trash. Agent requests and questions are answered in its bubble;
/// "Done" notes fade on their own.
@MainActor
final class MascotController {
    private let model: NotchModel
    private var panel: NSPanel?
    private var timer: Timer?
    private let state = MascotViewState()
    private var lastSessions: [AgentSession] = []

    init(model: NotchModel) { self.model = model }

    /// Shows or hides the mascot to match Settings › Mascot.
    func apply() {
        let s = model.mascot
        state.kind = s.kind
        if s.enabled { show() } else { hide() }
    }

    /// Agent state changed: update the bubble.
    func agentsChanged() {
        let current = model.agents.sessions
        if let note = MascotNotes.done(previous: lastSessions, current: current, title: { self.model.sessions.title(for: $0) }) {
            state.say(note)
        }
        lastSessions = current
        updateHitTesting()
    }

    private func show() {
        if panel == nil {
            let p = MascotPanel(contentRect: MascotGeometry.currentFrame(), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) // above the Dock
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            p.isMovable = false
            p.hidesOnDeactivate = false
            let root = MascotRoot(model: model, state: state, onInteractiveChange: { [weak self] _ in self?.updateHitTesting() })
            p.contentView = NSHostingView(rootView: root)
            panel = p
        }
        state.kind = model.mascot.kind
        reposition()
        updateHitTesting()
        panel?.orderFrontRegardless()
        // Follow the Dock if it moves, resizes or hides.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func reposition() {
        guard let panel else { return }
        let f = MascotGeometry.currentFrame()
        if panel.frame != f { panel.setFrame(f, display: true) }
    }

    /// Clicks pass through to the Dock and desktop except while a bubble is showing.
    private func updateHitTesting() {
        let interactive = !model.agents.pending.isEmpty || state.note != nil
        panel?.ignoresMouseEvents = !interactive
    }
}

@MainActor @Observable
final class MascotViewState {
    var kind: MascotKind = .kunoichi
    private(set) var note: String?
    @ObservationIgnored private var clear: DispatchWorkItem?

    func say(_ text: String, for seconds: TimeInterval = 8) {
        note = text
        clear?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.note = nil } }
        clear = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func dismiss() { clear?.cancel(); note = nil }
}

private struct MascotRoot: View {
    var model: NotchModel
    var state: MascotViewState
    var onInteractiveChange: (Bool) -> Void

    var body: some View {
        let agents = model.agents
        let first = agents.pending.first
        let talking = first != nil || state.note != nil
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if talking {
                VStack(alignment: .leading, spacing: 8) {
                    if let first {
                        switch first.kind {
                        case .permission(let tool, let input):
                            ApprovalCardView(request: first, tool: tool, input: input) { agents.decide(first.id, $0) }
                        case .question(let qs):
                            QuestionCardView(request: first, questions: qs) { agents.decide(first.id, $0) }.id(first.id)
                        }
                        if agents.pending.count > 1 {
                            Text("+\(agents.pending.count - 1) more waiting").font(Typo.ui(11)).foregroundStyle(model.tokens.muted)
                        }
                    } else if let note = state.note {
                        Button {
                            state.dismiss()
                            model.show(.agents)
                        } label: {
                            Text(note).font(Typo.ui(12.5, .semibold)).foregroundStyle(model.tokens.text).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(width: 330, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).fill(model.tokens.panel))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(model.tokens.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .padding(.trailing, 30)
                .padding(.bottom, MascotGeometry.characterSize.height + 6)
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            }
            MascotCharacter(kind: state.kind, talking: talking)
                .frame(width: MascotGeometry.characterSize.width, height: MascotGeometry.characterSize.height)
                .padding(.trailing, MascotGeometry.window.width - MascotGeometry.characterCenterX - MascotGeometry.characterSize.width / 2)
        }
        .frame(width: MascotGeometry.window.width, height: MascotGeometry.window.height)
        .environment(\.tokens, model.tokens)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: talking)
        .onChange(of: talking) { _, on in onInteractiveChange(on) }
    }
}
