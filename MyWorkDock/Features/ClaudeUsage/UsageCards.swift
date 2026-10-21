import Foundation

/// How the Tokens & cost tab writes numbers. Plain functions with no locale: a lakh-grouped "$1,23,456" would read as a typo.
enum UsageFormat {
    /// "$6,993.21"
    static func cost(_ usd: Double) -> String {
        let cents = Int((max(usd, 0) * 100).rounded())
        var grouped = ""
        for (i, digit) in String(cents / 100).reversed().enumerated() {
            if i > 0, i % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        let rest = cents % 100
        return "$\(String(grouped.reversed())).\(rest < 10 ? "0" : "")\(rest)"
    }

    /// "980", "1.2k", "612k", "497.1M", "171M", "14.46B": three significant digits, and a value that would round up to the next unit moves there.
    static func tokens(_ n: Int) -> String {
        let d = Double(max(n, 0))
        switch d {
        case ..<1_000: return String(Int(d))
        case ..<99_950: return String(format: "%.1fk", d / 1e3)
        case ..<999_500: return String(format: "%.0fk", d / 1e3)
        case ..<99_950_000: return String(format: "%.1fM", d / 1e6)
        case ..<999_500_000: return String(format: "%.0fM", d / 1e6)
        default: return String(format: "%.2fB", d / 1e9)
        }
    }

    /// The same four kinds the token-metrics plugin reports, in its order.
    static func split(_ t: TokenCounts) -> String {
        "input \(tokens(t.input)) · cache write \(tokens(t.cacheWrite)) · cache read \(tokens(t.cacheRead)) · output \(tokens(t.output))"
    }
}

/// One card of the tab, as plain text.
struct UsageCardModel: Identifiable, Equatable {
    var id: String
    var title: String
    var caption: String
    /// Last month with only part of its days: the caption turns to the warning colour and explains itself.
    var partial = false
    /// "$6,993.21", or "—" when there is nothing.
    var cost: String
    /// "14.46B tokens", or why there is nothing.
    var tokens: String
    var split: String
    var help: String?
}

enum UsageCards {
    static let partialHelp = "Claude Code deletes a transcript 30 days after its last write, so part of this month was already gone when MyWorkDock first looked, or before it looked again. Days before the date shown may be incomplete."
    static let untrackedHelp = "Claude Code had already deleted this month’s transcripts when MyWorkDock first looked. Anything shown is what survived."

    static func make(_ s: UsageSnapshot, calendar: Calendar = .current, locale: Locale = .current) -> [UsageCardModel] {
        func text(_ date: Date, _ build: (Date.FormatStyle) -> Date.FormatStyle) -> String {
            date.formatted(build(Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)))
        }
        func card(_ id: String, _ title: String, caption: String, _ f: UsageFigures, empty: String, partial: Bool = false, help: String? = nil) -> UsageCardModel {
            let none = f.tokens.total == 0
            return UsageCardModel(id: id, title: title, caption: caption, partial: partial,
                                  cost: none ? "—" : UsageFormat.cost(f.cost),
                                  tokens: none ? empty : "\(UsageFormat.tokens(f.tokens.total)) tokens",
                                  split: none ? "" : UsageFormat.split(f.tokens), help: help)
        }
        /// A month: its name, or when it may be incomplete the day it can be trusted from (`end` is where the month stops).
        func month(_ id: String, _ title: String, start: Date, end: Date, _ f: UsageFigures, from: Date?, empty: String) -> UsageCardModel {
            guard let from else { return card(id, title, caption: text(start) { $0.month(.wide).year() }, f, empty: empty) }
            let whole = from >= end // the month ended before anything could be vouched for
            return card(id, title, caption: whole ? "not tracked" : "partial · from " + text(from) { $0.month(.abbreviated).day() }, f, empty: empty,
                        partial: true, help: whole ? untrackedHelp : partialHelp)
        }
        let since = s.windowSince.map { "since " + text($0) { $0.hour().minute() } } ?? "rolling window"
        return [
            card("five", "Last 5 hours", caption: since, s.fiveHours, empty: "no usage in the last 5 hours"),
            card("today", "Today", caption: text(s.updatedAt) { $0.weekday(.abbreviated).day().month(.abbreviated) }, s.today, empty: "no usage yet today"),
            month("month", "This month", start: s.monthStart, end: s.updatedAt, s.month, from: s.monthPartialFrom, empty: "no usage this month"),
            month("last", "Last month", start: s.lastMonthStart, end: s.monthStart, s.lastMonth, from: s.lastMonthPartialFrom, empty: "no data for last month"),
        ]
    }
}
