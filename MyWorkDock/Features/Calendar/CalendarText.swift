import SwiftUI

/// "Weekly on Wednesday": Google's own wording for a series' rule, for the common rules. Anything else reads "Repeats".
enum Recurrence {
    private static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
    private static let ordinals = [1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth", -1: "last"]

    static func describe(_ lines: [String], start: Date, cal: Calendar) -> String {
        guard let line = lines.first(where: { $0.uppercased().hasPrefix("RRULE:") }) else { return "Repeats" }
        var rule: [String: String] = [:]
        for part in line.dropFirst("RRULE:".count).split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { rule[pair[0].uppercased()] = pair[1] }
        }
        guard rule["BYSETPOS"] == nil else { return "Repeats" }
        let interval = max(1, Int(rule["INTERVAL"] ?? "") ?? 1)
        func weekday(_ code: String) -> String? { weekdays[code].map { cal.weekdaySymbols[$0 - 1] } }

        var text: String
        switch rule["FREQ"] {
        case "DAILY":
            text = interval == 1 ? "Daily" : "Every \(interval) days"
        case "WEEKLY":
            let codes = (rule["BYDAY"] ?? "").split(separator: ",").map(String.init)
            if interval == 1, Set(codes) == ["MO", "TU", "WE", "TH", "FR"] {
                text = "Every weekday"
            } else {
                let names = codes.compactMap(weekday)
                let on = names.isEmpty ? [cal.weekdaySymbols[cal.component(.weekday, from: start) - 1]] : names
                text = (interval == 1 ? "Weekly" : "Every \(interval) weeks") + " on " + on.joined(separator: ", ")
            }
        case "MONTHLY":
            let prefix = interval == 1 ? "Monthly" : "Every \(interval) months"
            if let byDay = rule["BYDAY"] {
                guard let ordinal = Int(byDay.dropLast(2)), let word = ordinals[ordinal], let name = weekday(String(byDay.suffix(2))) else { return "Repeats" }
                text = "\(prefix) on the \(word) \(name)"
            } else {
                text = "\(prefix) on day \(rule["BYMONTHDAY"] ?? String(cal.component(.day, from: start)))"
            }
        case "YEARLY":
            text = (interval == 1 ? "Annually" : "Every \(interval) years") + " on " + start.formatted(.dateTime.month(.wide).day())
        default:
            return "Repeats"
        }
        if let count = rule["COUNT"].flatMap({ Int($0) }) {
            text += ", \(count) time\(count == 1 ? "" : "s")"
        } else if let until = rule["UNTIL"].flatMap({ date(String($0.prefix(8)), cal) }) {
            text += ", until " + until.formatted(.dateTime.day().month(.abbreviated).year())
        }
        return text
    }

    /// `20261231` as a local day.
    private static func date(_ digits: String, _ cal: Calendar) -> Date? {
        guard digits.count == 8, let year = Int(digits.prefix(4)), let month = Int(digits.dropFirst(4).prefix(2)), let day = Int(digits.suffix(2)) else { return nil }
        return cal.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// An event's description as styled text. Google sends HTML for events made in the Calendar UI and plain text from other
/// tools: this handles both with a tag scanner, never `NSAttributedString(html:)` (slow, WebKit, main thread). Bold, italic,
/// underline, links, line breaks and bullets are kept; every other tag is dropped. Only http(s) and mailto links are live.
enum RichText {
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]
    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]

    static func attributed(html: String, limit: Int = 20_000) -> AttributedString {
        let source = html.replacingOccurrences(of: "\r\n", with: "\n")
        var out = AttributedString()
        var bold = 0
        var italic = 0
        var underline = 0
        var link: URL?
        var newlines = 0 // line breaks at the end of `out`, capped at two so the text never gaps wider than a blank line
        var written = 0
        var truncated = false

        func add(_ text: String) {
            var piece = AttributedString(text)
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if underline > 0 || link != nil { piece.underlineStyle = .single }
            if let link { piece.link = link }
            out += piece
        }
        func lineBreak() {
            guard newlines < 2, !out.characters.isEmpty else { return }
            add("\n")
            newlines += 1
        }
        func text(_ raw: String) {
            for (offset, part) in decode(raw).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if offset > 0 { lineBreak() }
                let kept = part.prefix(max(0, limit - written))
                if kept.count < part.count { truncated = true }
                if !kept.isEmpty {
                    add(String(kept))
                    newlines = 0
                    written += kept.count
                }
            }
        }
        func handle(_ tag: String) {
            let lower = tag.lowercased()
            let closing = lower.hasPrefix("/")
            let name = String(lower.drop { $0 == "/" }.prefix { $0 != " " && $0 != "/" && $0 != "\n" })
            if closing {
                switch name {
                case "p", "div", "li", "tr", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6": lineBreak()
                case "b", "strong": bold = max(0, bold - 1)
                case "i", "em": italic = max(0, italic - 1)
                case "u": underline = max(0, underline - 1)
                case "a": link = nil
                default: break
                }
            } else {
                switch name {
                case "br": lineBreak()
                case "li":
                    if newlines == 0 { lineBreak() } // the previous item's </li> already broke the line
                    add("• ")
                    newlines = 0
                case "b", "strong": bold += 1
                case "i", "em": italic += 1
                case "u": underline += 1
                case "a": link = href(in: tag)
                default: break
                }
            }
        }

        var index = source.startIndex
        while index < source.endIndex {
            if truncated { break }
            // A tag starts with "<" and a letter or "/": "1 < 2" is text.
            let afterBracket = source.index(after: index)
            if source[index] == "<", afterBracket < source.endIndex, source[afterBracket].isLetter || source[afterBracket] == "/",
               let close = source[index...].firstIndex(of: ">") {
                let tag = String(source[afterBracket..<close]).trimmingCharacters(in: .whitespaces)
                let name = tag.lowercased().prefix { $0 != " " && $0 != "/" }
                if name == "script" || name == "style" {
                    // Their content is code, not text: skip to the closing tag.
                    index = source.range(of: "</\(name)>", options: .caseInsensitive, range: close..<source.endIndex)?.upperBound ?? source.endIndex
                    continue
                }
                handle(tag)
                index = source.index(after: close)
            } else {
                // Text up to the next "<"; a "<" that opens no tag is part of it.
                let from = source[index] == "<" ? afterBracket : index
                let stop = source[from...].firstIndex(of: "<") ?? source.endIndex
                text(String(source[index..<stop]))
                index = stop
            }
        }
        while out.characters.last == "\n" { out.characters.removeLast() }
        if truncated { out += AttributedString("…") }
        linkify(&out)
        return out
    }

    /// Bare addresses in the text become links too (Google shows them as links).
    private static func linkify(_ text: inout AttributedString) {
        let plain = String(text.characters)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let url = match.url, linkSchemes.contains(url.scheme?.lowercased() ?? ""), let range = Range(match.range, in: plain) else { continue }
            let lower = text.index(text.startIndex, offsetByCharacters: plain.distance(from: plain.startIndex, to: range.lowerBound))
            let upper = text.index(lower, offsetByCharacters: plain.distance(from: range.lowerBound, to: range.upperBound))
            guard text[lower..<upper].runs.allSatisfy({ $0.link == nil }) else { continue }
            text[lower..<upper].link = url
            text[lower..<upper].underlineStyle = .single
        }
    }

    private static func href(in tag: String) -> URL? {
        guard let attribute = tag.range(of: "href", options: .caseInsensitive) else { return nil }
        var rest = tag[attribute.upperBound...].drop { $0 == " " }
        guard rest.first == "=" else { return nil }
        rest = rest.dropFirst().drop { $0 == " " }
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        let value = decode(String(rest.dropFirst().prefix { $0 != quote }))
        guard let url = URL(string: value), linkSchemes.contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].prefix(10).firstIndex(of: ";") {
                let entity = String(text[text.index(after: index)..<semicolon])
                if let replacement = named[entity] ?? numeric(entity) {
                    out += replacement
                    index = text.index(after: semicolon)
                    continue
                }
            }
            out.append(text[index])
            index = text.index(after: index)
        }
        return out
    }

    private static func numeric(_ entity: String) -> String? {
        guard entity.hasPrefix("#") else { return nil }
        let digits = entity.dropFirst()
        let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}

/// How the sheet says when an event is.
enum EventText {
    private static let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
    private static let dayAndTime = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()

    static func when(_ event: CalendarEvent, cal: Calendar) -> String {
        if event.allDay {
            let last = cal.date(byAdding: .day, value: -1, to: event.end) ?? event.start
            if cal.isDate(last, inSameDayAs: event.start) { return "\(event.start.formatted(day)) · All day" }
            return "\(event.start.formatted(day)) – \(last.formatted(day)) · All day"
        }
        // An event that ends exactly at midnight still belongs to the day it started on.
        let lastMoment = event.end > event.start ? event.end.addingTimeInterval(-1) : event.end
        if cal.isDate(event.start, inSameDayAs: lastMoment) {
            return "\(event.start.formatted(day)) · " + (event.start..<max(event.end, event.start)).formatted(Date.IntervalFormatStyle(time: .shortened))
        }
        return "\(event.start.formatted(dayAndTime)) – \(event.end.formatted(dayAndTime))"
    }
}
