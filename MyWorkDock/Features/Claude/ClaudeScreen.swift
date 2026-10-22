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
            case .sessions: SubTabItem(tab.rawValue, "Sessions", count: model.sessions.transcripts.isEmpty ? nil : model.sessions.transcripts.count)
            case .tokens: SubTabItem(tab.rawValue, "Tokens & cost")
            }
        }
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
