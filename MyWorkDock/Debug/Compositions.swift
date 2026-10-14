import SwiftUI

// Screen-level compositions of the components with sample data, used by the snapshot fragments and the gallery.
// They hold no behaviour.

enum SubNav {
    static let notes = [SubTabItem("todo", "TODO", count: 3), SubTabItem("commands", "Commands", count: 6), SubTabItem("prompts", "Prompts", count: 5),
                         SubTabItem("links", "Links", count: 4)]
    static let claudex = [SubTabItem("usage", "Usage", count: 3), SubTabItem("pool", "Pool", count: 11),
                          SubTabItem("play", "Playground"), SubTabItem("health", "Health")]
    static let emulator = [SubTabItem("devices", "Devices", glyph: .phone), SubTabItem("wireless", "Wireless", glyph: .wifi),
                           SubTabItem("tunnel", "Tunnel", glyph: .arrows)]
}

/// Draws `content` on the `card` fill, for fragments of components that sit inside a card in the real screen.
struct OnCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.tokens) private var t

    var body: some View { content.background(t.card) }
}
