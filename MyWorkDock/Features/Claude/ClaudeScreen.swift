import SwiftUI

/// The Claude menu's sub-tabs.
enum ClaudeTab: String, CaseIterable { case sessions, agents, tokens }

/// Claude: Sessions (the board), Agents (requests and live sessions) and Tokens & cost (from Claude Code's transcripts).
struct ClaudeScreen: View {
    var model: NotchModel

    var body: some View {
        let usage = model.claudeUsage
        VStack(spacing: 0) {
            SubNavRow(items: tabs, selection: model.claudeTab.rawValue, onSelect: { model.setClaudeTab(ClaudeTab(rawValue: $0) ?? .sessions) }) {
                if model.claudeTab == .tokens { FreshLabel { usage.freshLabel } }
                PillButton(title: "Refresh", glyph: .refresh, iconSize: 13,
                           busy: model.claudeRefreshing || model.sessions.loading || usage.loading) {
                    Task { await model.refreshClaude() }
                }
                .help("Reload sessions, the agents' setup and Tokens & cost")
            }
            .padding(.top, Geo.Chrome.subNavTop)

            Group {
                switch model.claudeTab {
                case .sessions: SessionsScreen(model: model)
                case .agents: AgentsScreen(model: model)
                case .tokens: TokensView(store: usage)
                }
            }
            .padding(.top, Geo.Chrome.contentTop)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var tabs: [SubTabItem] {
        let sessions = model.sessions.transcripts.count, waiting = model.agents.pending.count
        return [SubTabItem(ClaudeTab.sessions.rawValue, "Sessions", count: sessions > 0 ? sessions : nil),
                SubTabItem(ClaudeTab.agents.rawValue, "Agents", count: waiting > 0 ? waiting : nil),
                SubTabItem(ClaudeTab.tokens.rawValue, "Tokens & cost")]
    }
}

/// A Claude sub-tab with nothing to list yet, or still loading: a dashed box with an icon (a spinner while loading), a title and a line
/// of help, centred in the space it is given.
struct ClaudePlaceholder: View {
    var glyph: Glyph
    var title: String
    var message: String
    var loading = false
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if loading { Spinner(size: 20) } else { Icon(glyph, size: 20) }
            }
            .foregroundStyle(t.muted)
            .frame(width: 40, height: 40)
            .background(Circle().fill(t.ctrl))
            Text(title).font(Typo.ui(13.5, .semibold)).foregroundStyle(t.text2)
            Text(message)
                .font(Typo.ui(12)).foregroundStyle(t.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(t.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .accessibilityElement(children: .combine)
    }
}
