import Foundation

/// What one API call (or a sum of calls) sent and received, split the way the API bills it.
struct TokenCounts: Codable, Equatable, Sendable {
    var input = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0
    var output = 0

    init(input: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.output = output
    }

    /// A saved file from a version that wrote fewer fields still loads: what it did not write is 0. A count below 0 can only be a damaged file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int { max(0, try c.decodeIfPresent(Int.self, forKey: key) ?? 0) }
        input = try count(.input)
        cacheWrite5m = try count(.cacheWrite5m)
        cacheWrite1h = try count(.cacheWrite1h)
        cacheRead = try count(.cacheRead)
        output = try count(.output)
    }

    private enum CodingKeys: String, CodingKey { case input, cacheWrite5m, cacheWrite1h, cacheRead, output }

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    /// Every token a call sends or receives, cache reads included (the token-metrics plugin's headline).
    var total: Int { input + cacheWrite + cacheRead + output }

    static func += (a: inout TokenCounts, b: TokenCounts) {
        a.input += b.input
        a.cacheWrite5m += b.cacheWrite5m
        a.cacheWrite1h += b.cacheWrite1h
        a.cacheRead += b.cacheRead
        a.output += b.output
    }

    /// Per field, `a - b`. Only used for the growth of one call, where `a` is never below `b`.
    static func - (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input - b.input, cacheWrite5m: a.cacheWrite5m - b.cacheWrite5m, cacheWrite1h: a.cacheWrite1h - b.cacheWrite1h,
                    cacheRead: a.cacheRead - b.cacheRead, output: a.output - b.output)
    }

    /// Per field maximum. A streamed message repeats its `usage` on every chunk and only the output grows,
    /// so the largest value of each field is the final one.
    func raised(to o: TokenCounts) -> TokenCounts {
        TokenCounts(input: max(input, o.input), cacheWrite5m: max(cacheWrite5m, o.cacheWrite5m), cacheWrite1h: max(cacheWrite1h, o.cacheWrite1h),
                    cacheRead: max(cacheRead, o.cacheRead), output: max(output, o.output))
    }
}

/// Stable 64-bit key of a message id. Swift's own `hashValue` is different on every launch, so it cannot be saved.
struct CallKey: Hashable, Codable, Sendable {
    let raw: UInt64

    init(raw: UInt64) { self.raw = raw }

    /// FNV-1a over the id's UTF-8 bytes.
    init(_ id: String) {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 { h = (h ^ UInt64(byte)) &* 0x100_0000_01b3 }
        raw = h
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let value = UInt64(text, radix: 16) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a hex key: \(text)"))
        }
        raw = value
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(raw, radix: 16))
    }
}

/// One API call as a transcript records it.
struct ParsedCall: Equatable, Sendable {
    var key: CallKey
    /// Seconds since 1970: the first chunk of the message.
    var t: Double
    var model: String
    var tokens: TokenCounts
}

struct UsageFigures: Equatable, Sendable {
    var tokens = TokenCounts()
    /// API-equivalent list price, not what a subscription bills.
    var cost = 0.0

    mutating func add(_ t: TokenCounts, model: String) {
        tokens += t
        cost += UsagePricing.cost(t, model: model)
    }
}

/// Everything the Tokens & cost tab shows.
struct UsageSnapshot: Equatable, Sendable {
    /// The last five hours, rolling: a limit window cannot be rebuilt from transcripts (it belongs to an account).
    var fiveHours = UsageFigures()
    /// First call inside the five hours; nil when there was none.
    var windowSince: Date?
    var today = UsageFigures()
    var month = UsageFigures()
    var lastMonth = UsageFigures()
    var monthStart: Date
    var lastMonthStart: Date
    /// Set when that month may be incomplete: Claude Code deletes a transcript 30 days after its last write, so what happened before the
    /// first look (or in a stretch longer than 30 days between two looks) can be gone. The first day its numbers can be trusted from.
    var monthPartialFrom: Date?
    var lastMonthPartialFrom: Date?
    var updatedAt: Date
    /// No transcript was found and nothing was saved earlier: Claude Code is not used here, or keeps its files elsewhere.
    var noData = false
}
