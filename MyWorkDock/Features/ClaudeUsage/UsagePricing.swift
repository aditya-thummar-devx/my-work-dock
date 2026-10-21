import Foundation

struct ModelPrice: Equatable, Sendable {
    /// USD per million tokens. Cache writes are priced from `input`.
    var input: Double
    var output: Double
    var cacheRead: Double
}

/// API list prices, same table and method as the token-metrics plugin (`leak_report.py`): a flat price per model version, cache writes at
/// 1.25x input for the 5-minute cache and 2x for the 1-hour cache, no long-context or fast-mode multiplier. Compared with the session
/// costs Claude Code records itself, Opus 5 and 5.5 match exactly and Opus 4.8 is within 3 %; Sonnet 5.5 can come out too high.
/// ponytail: update by hand when Anthropic changes prices or ships a model; an unknown version falls back to its family.
enum UsagePricing {
    static let write5m = 1.25
    static let write1h = 2.0

    /// Longest id first, so "claude-opus-5-5" wins over "claude-opus-5".
    private static let versions: [(id: String, price: ModelPrice)] = {
        let all: [(id: String, price: ModelPrice)] = [
            ("claude-fable-5-1", ModelPrice(input: 10, output: 50, cacheRead: 0.25)),
            ("claude-fable-5", ModelPrice(input: 10, output: 50, cacheRead: 1)),
            ("claude-opus-5-5", ModelPrice(input: 4, output: 20, cacheRead: 0.2)),
            ("claude-opus-5", ModelPrice(input: 5, output: 25, cacheRead: 0.5)),
            ("claude-opus-4-8", ModelPrice(input: 5, output: 25, cacheRead: 0.5)),
            ("claude-opus-4-7", ModelPrice(input: 5, output: 25, cacheRead: 0.5)),
            ("claude-opus-4-6", ModelPrice(input: 5, output: 25, cacheRead: 0.5)),
            ("claude-opus-4-5", ModelPrice(input: 5, output: 25, cacheRead: 0.5)),
            ("claude-sonnet-5-5", ModelPrice(input: 2, output: 10, cacheRead: 0.2)),
            ("claude-sonnet-5", ModelPrice(input: 2, output: 10, cacheRead: 0.2)),
            ("claude-sonnet-4-6", ModelPrice(input: 3, output: 15, cacheRead: 0.3)),
            ("claude-sonnet-4-5", ModelPrice(input: 3, output: 15, cacheRead: 0.3)),
            ("claude-haiku-4-5", ModelPrice(input: 1, output: 5, cacheRead: 0.1)),
        ]
        return all.sorted { $0.id.count > $1.id.count }
    }()

    /// A version not listed above is priced as its family's current model.
    private static let families: [(name: String, price: ModelPrice)] = [
        ("fable", ModelPrice(input: 10, output: 50, cacheRead: 0.25)),
        ("opus", ModelPrice(input: 4, output: 20, cacheRead: 0.2)),
        ("sonnet", ModelPrice(input: 2, output: 10, cacheRead: 0.2)),
        ("haiku", ModelPrice(input: 1, output: 5, cacheRead: 0.1)),
    ]

    static func price(for model: String) -> ModelPrice {
        let m = model.lowercased()
        if let v = versions.first(where: { m.contains($0.id) }) { return v.price }
        return families.first(where: { m.contains($0.name) })?.price ?? families[2].price
    }

    static func cost(_ t: TokenCounts, model: String) -> Double {
        let p = price(for: model)
        let writes5m: Double = Double(t.cacheWrite5m) * write5m
        let writes1h: Double = Double(t.cacheWrite1h) * write1h
        let inputUnits: Double = Double(t.input) + writes5m + writes1h
        let inputCost: Double = inputUnits * p.input
        let readCost: Double = Double(t.cacheRead) * p.cacheRead
        let outputCost: Double = Double(t.output) * p.output
        return (inputCost + readCost + outputCost) / 1e6
    }
}
