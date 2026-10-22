import SwiftUI

/// Tokens & cost: what Claude Code used on this Mac, as four cards. Looks again every minute while it is on screen.
struct TokensView: View {
    var store: ClaudeUsageStore
    @Environment(\.staticRender) private var staticRender
    @Environment(\.tokens) private var t

    var body: some View {
        content
            .task {
                guard !staticRender else { return }
                store.activate()
                while !Task.isCancelled {
                    await store.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let snapshot = store.snapshot {
            if snapshot.noData { empty } else { cards }
        } else {
            HStack(spacing: 8) {
                Spinner(size: 14).foregroundStyle(t.muted)
                Text("Reading Claude Code’s transcripts. The first look can take a few seconds.").font(Typo.ui(12.5)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var cards: some View {
        DockScroll {
            VStack(alignment: .leading, spacing: 10) {
                CardGrid(items: store.cards) { UsageCard(card: $0) }
                Text("Claude Code on this Mac, every account and every subagent. Cost is what the same tokens would cost at API list prices, not your plan’s bill.")
                    .font(Typo.ui(11.5)).foregroundStyle(t.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                if let why = store.saveError {
                    Text("Could not save the totals: \(why)").font(Typo.ui(11.5, .semibold)).foregroundStyle(t.orange).padding(.horizontal, 4)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No Claude Code usage found").font(Typo.ui(13, .semibold)).foregroundStyle(t.text2)
            Text("Nothing under ~/.claude/projects yet. Use Claude Code on this Mac and the totals appear here.")
                .font(Typo.ui(12.5)).foregroundStyle(t.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// One period: cost as the headline, tokens beside it, the four kinds of token underneath.
struct UsageCard: View {
    var card: UsageCardModel
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 16, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.title).font(Typo.ui(13.5, .bold))
                    Spacer(minLength: 0)
                    Text(card.caption)
                        .font(Typo.ui(11.5, card.partial ? .semibold : .regular))
                        .foregroundStyle(card.partial ? t.orange : t.faint)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(card.cost).font(Typo.display(27)).tracking(-0.5).foregroundStyle(t.text)
                    Text(card.tokens).font(Typo.ui(12.5, .semibold)).foregroundStyle(t.muted).lineLimit(1)
                }
                Text(card.split.isEmpty ? " " : card.split)
                    .font(Typo.ui(11)).foregroundStyle(t.faint)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(card.help ?? "")
        .accessibilityElement(children: .combine)
    }
}
