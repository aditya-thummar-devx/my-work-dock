import SwiftUI

/// Agents: requests waiting for you on the left, live sessions (with a message box) on the right.
struct AgentsScreen: View {
    var model: NotchModel
    @Environment(\.tokens) private var t

    var body: some View {
        let store = model.agents
        VStack(alignment: .leading, spacing: 12) {
            SetupBanner(store: store).padding(.top, Geo.Chrome.subNavTop)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Waiting for you", count: store.pending.count)
                    if store.pending.isEmpty {
                        EmptyHint(text: "Nothing to approve. Claude's permission prompts and questions show up here.")
                    } else {
                        DockScroll {
                            VStack(spacing: 10) {
                                ForEach(store.pending) { p in
                                    switch p.kind {
                                    case .permission(let tool, let input):
                                        ApprovalCardView(request: p, tool: tool, input: input) { store.decide(p.id, $0) }
                                    case .question(let qs):
                                        QuestionCardView(request: p, questions: qs) { store.decide(p.id, $0) }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 330)
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Live sessions", count: store.sessions.count)
                    if store.sessions.isEmpty {
                        EmptyHint(text: "No active agents. Start Claude Code and it appears here.")
                    } else {
                        DockScroll {
                            VStack(spacing: 8) {
                                ForEach(store.sessions) { s in
                                    SessionRowView(store: store, session: s, title: model.sessions.title(for: s.transcriptID),
                                                   onShowOnBoard: { model.showOnBoard(s.transcriptID) })
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task { store.refreshHooks() }
    }
}

private struct SectionLabel: View {
    var text: String
    var count: Int
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(Typo.ui(12, .semibold)).foregroundStyle(t.text2)
            if count > 0 { CountBadge(count: count, on: text == "Waiting for you") }
        }
        .padding(.horizontal, 4)
    }
}

/// One global switch: installs or repairs MyWorkDock's Claude hooks for every session.
private struct SetupBanner: View {
    var store: AgentStore
    @Environment(\.tokens) private var t

    var body: some View {
        let h = store.hooks
        if let err = h.error ?? store.serverError {
            Text(err).font(Typo.ui(12)).foregroundStyle(t.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        } else if !h.installed || h.stale {
            Card(radius: 14, border: t.accent.opacity(0.5), padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10)) {
                HStack(spacing: 10) {
                    Icon(.chat, size: 14)
                    Text(h.installed ? "Agent approvals and messaging need an update." : "Approve Claude's requests and message its sessions from here.")
                        .font(Typo.ui(12.5)).foregroundStyle(t.text)
                    Spacer(minLength: 0)
                    DockButton(title: h.installed ? "Repair" : "Set up", glyph: nil, metrics: .card, tone: .tint, busy: store.installing,
                               action: store.installHooks)
                }
            }
        }
    }
}

private func detail(_ input: JSONValue) -> String {
    for k in ["command", "file_path", "path", "url", "pattern"] { if let s = input[k]?.string { return s } }
    if case .null = input { return "" }
    return String(decoding: (try? JSONEncoder().encode(input)) ?? Data(), as: UTF8.self).prefix(200).description
}

struct ApprovalCardView: View {
    var request: PendingRequest
    var tool: String
    var input: JSONValue
    var onDecide: (AgentDecision) -> Void
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 16, border: t.orange.opacity(0.55), padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tool).font(Typo.display(17)).tracking(-0.3)
                    Spacer()
                    TagChip(tag: request.project)
                }
                let d = detail(input)
                if !d.isEmpty {
                    Text(d).font(Typo.mono(11.5)).foregroundStyle(t.text2).lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8).background(RoundedRectangle(cornerRadius: 9).fill(t.inset))
                }
                HStack(spacing: 6) {
                    DockButton(title: "Allow", glyph: .check, metrics: .card, tone: .tint) { onDecide(.allow(always: false)) }
                    DockButton(title: "Always", glyph: nil, metrics: .card, tone: .secondary) { onDecide(.allow(always: true)) }
                        .help(AlwaysRule.commandScoped.contains(tool) ? "Always allow this exact command in \(request.project)" : "Always allow \(tool) in \(request.project)")
                    DockButton(title: "Deny", glyph: nil, metrics: .card, tone: .stop) { onDecide(.deny(reason: nil)) }
                    Spacer(minLength: 0)
                    DockButton(title: "Terminal", glyph: .terminal, metrics: .card, tone: .ctrl) { onDecide(.passthrough) }
                }
            }
        }
    }
}

struct QuestionCardView: View {
    var request: PendingRequest
    var questions: [AgentQuestion]
    var onDecide: (AgentDecision) -> Void
    @State private var picked: [Int: [String]] = [:]
    @State private var other: [Int: String] = [:]
    @Environment(\.tokens) private var t

    private var answers: [QuestionAnswer] {
        questions.enumerated().map { i, q in
            let typed = (other[i] ?? "").trimmingCharacters(in: .whitespaces)
            // Multi-select labels are comma-joined, as Claude Code expects.
            return QuestionAnswer(question: q.question, answer: typed.isEmpty ? (picked[i] ?? []).joined(separator: ", ") : typed)
        }
    }

    var body: some View {
        Card(radius: 16, border: t.accent.opacity(0.5), padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Claude has a question").font(Typo.ui(12, .semibold)).foregroundStyle(t.muted)
                    Spacer()
                    TagChip(tag: request.project)
                }
                ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.question).font(Typo.ui(13, .semibold))
                        FlowRow(spacing: 6) {
                            ForEach(q.options, id: \.self) { o in
                                let on = picked[i]?.contains(o.label) ?? false
                                Button {
                                    var sel = picked[i] ?? []
                                    if q.multiSelect { if on { sel.removeAll { $0 == o.label } } else { sel.append(o.label) } } else { sel = [o.label] }
                                    picked[i] = sel
                                } label: {
                                    Text(o.label).font(Typo.ui(12, .semibold))
                                        .foregroundStyle(on ? Tokens.onTint : t.text)
                                        .padding(.horizontal, 10).frame(height: 26)
                                        .background(Capsule().fill(on ? t.accent : t.ctrl))
                                }
                                .buttonStyle(.plain)
                                .help(o.description ?? "")
                            }
                        }
                        DockTextField(text: Binding(get: { other[i] ?? "" }, set: { other[i] = $0 }), placeholder: "Other…", font: Typo.ui(12))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 9).fill(t.inset))
                    }
                }
                HStack(spacing: 6) {
                    DockButton(title: "Send", glyph: .check, metrics: .card, tone: .tint, enabled: answers.allSatisfy { !$0.answer.isEmpty }) {
                        onDecide(.answer(answers))
                    }
                    Spacer(minLength: 0)
                    DockButton(title: "Answer in terminal", glyph: .terminal, metrics: .card, tone: .ctrl) { onDecide(.passthrough) }
                }
            }
        }
    }
}

struct SessionRowView: View {
    var store: AgentStore
    var session: AgentSession
    var title: String?
    var onShowOnBoard: () -> Void = {}
    @State private var text = ""
    @Environment(\.tokens) private var t

    var body: some View {
        let s = session
        let idleUnreachable = s.state == .idle && !s.reachable && !s.canTypeInto
        Card(radius: 14, padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title ?? s.project).font(Typo.ui(13, .semibold)).lineLimit(1)
                    StateChip(state: s.state)
                    if s.queued > 0 { Text("\(s.queued) queued").font(Typo.ui(11)).foregroundStyle(t.muted) }
                    Spacer(minLength: 0)
                    if let term = s.terminal { TagChip(tag: term) }
                }
                HStack(spacing: 8) {
                    if title != nil { Text(s.project).font(Typo.ui(11.5)).foregroundStyle(t.muted) }
                    if let a = s.lastAction { Text(a).font(Typo.ui(11.5)).foregroundStyle(t.muted).lineLimit(1) }
                    Spacer(minLength: 0)
                    Button("Show on board", action: onShowOnBoard).buttonStyle(.plain)
                        .font(Typo.ui(11.5, .semibold)).foregroundStyle(t.accent)
                }
                HStack(spacing: 6) {
                    DockTextField(text: $text,
                                  placeholder: idleUnreachable ? "Send one prompt in \(s.terminal ?? "its terminal") first" :
                                    (s.state == .working && !s.canTypeInto ? "Message Claude… (sent when this turn ends)" : "Message Claude…"),
                                  font: Typo.ui(12))
                        .onSubmit(send)
                        .disabled(idleUnreachable)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 9).fill(t.inset))
                    DockButton(title: "Send", glyph: nil, metrics: .card, tone: .tint,
                               enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty && !idleUnreachable,
                               busy: store.sending.contains(s.id), action: send)
                }
                if let note = store.notes[s.id] {
                    Text(note.text).font(Typo.ui(11)).foregroundStyle(note.error ? t.red : t.muted)
                }
                if !s.canTypeInto {
                    Text("\(s.terminal ?? "This terminal") can't be typed into, so messages reach Claude as a note rather than a real prompt.")
                        .font(Typo.ui(10.5)).foregroundStyle(t.faint)
                }
            }
        }
    }

    private func send() {
        let msg = text
        guard !msg.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        text = ""
        Task { await store.send(session.id, msg) }
    }
}

private struct StateChip: View {
    var state: AgentState
    @Environment(\.tokens) private var t

    var body: some View {
        let (bg, fg): (Color, Color) = switch state {
        case .working: (t.greenBg, t.green)
        case .waiting: (t.orangeBg, t.orange)
        case .idle, .ended: (t.grayBg, t.gray)
        }
        Text(state.label).font(Typo.ui(10.5, .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(bg))
    }
}

/// Wrapping row of chips.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
