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
                if model.claudeTab == .tokens {
                    FreshLabel { usage.freshLabel }
                    PillButton(title: "Refresh", glyph: .refresh, iconSize: 13, action: usage.refreshNow)
                }
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
        [SubTabItem(ClaudeTab.sessions.rawValue, "Sessions", count: model.sessions.transcripts.count),
         SubTabItem(ClaudeTab.agents.rawValue, "Agents", count: model.agents.pending.count),
         SubTabItem(ClaudeTab.tokens.rawValue, "Tokens & cost")]
    }
}
