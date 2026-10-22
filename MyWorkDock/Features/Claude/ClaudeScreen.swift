import SwiftUI

/// Claude Code's own tools, one menu: who is waiting on you (Agents), the board of its sessions and what it spent (Tokens & cost).
/// The raw values are stored in UserDefaults through `SubMenu`.
enum ClaudeTab: String, CaseIterable { case agents, sessions, tokens }

struct ClaudeScreen: View {
    var model: NotchModel

    var body: some View {
        let tab = model.enabledClaudeTabs.contains(model.claudeTab) ? model.claudeTab : model.enabledClaudeTabs.first ?? model.claudeTab
        VStack(spacing: 0) {
            SubNavRow(items: items, selection: tab.rawValue, onSelect: { model.setClaudeTab(ClaudeTab(rawValue: $0) ?? .agents) }) {
                if tab == .tokens {
                    FreshLabel { model.claudeUsage.freshLabel }
                    PillButton(title: "Refresh", glyph: .refresh, iconSize: 13, action: model.claudeUsage.refreshNow)
                }
            }
            .padding(.top, Geo.Chrome.subNavTop)

            Group {
                switch tab {
                case .tokens: TokensView(store: model.claudeUsage)
                case .agents: AgentsScreen(model: model)
                case .sessions: SessionsScreen(model: model)
                }
            }
            .padding(.top, tab == .tokens ? Geo.Chrome.contentTop : Geo.Chrome.contentTopClaudex)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var items: [SubTabItem] {
        model.enabledClaudeTabs.map { tab in
            switch tab {
            case .agents: SubTabItem(tab.rawValue, "Agents", count: model.agents.waitingCount > 0 ? model.agents.waitingCount : nil)
            case .sessions: SubTabItem(tab.rawValue, "Sessions")
            case .tokens: SubTabItem(tab.rawValue, "Tokens & cost")
            }
        }
    }
}
