import Foundation

/// Claude Code transcripts (`~/.claude/projects/**/*.jsonl`, subagents included) are append-only JSON lines. An assistant line carries
/// `message.usage`. One API call is written as several lines, one per streamed content block, that repeat the same `message.id` and
/// `usage`; only `output_tokens` grows, so the first chunk gives the start time and the largest value of each field is the final one.
/// A resumed or forked session copies old lines into a new file, so the same id can also appear in two files (see `UsageLedger`).
///
/// The format is not documented. Anything unrecognised is skipped, never guessed.
enum TranscriptParser {
    private static let usageKey: [UInt8] = Array("\"usage\"".utf8)
    private static let assistantKey: [UInt8] = Array("assistant".utf8)

    /// Folds every complete line of `lines` into `calls`.
    static func parse(_ lines: UnsafeRawBufferPointer, into calls: inout [CallKey: ParsedCall]) {
        guard let base = lines.baseAddress else { return }
        var pos = 0
        while pos < lines.count {
            let rest = base + pos
            let remaining = lines.count - pos
            var len = remaining
            if let nl = memchr(rest, 0x0A, remaining) { len = rest.distance(to: UnsafeRawPointer(nl)) }
            // Most lines are prompts and tool results: skip them with a byte search before paying for a JSON parse.
            if len > 40, memmem(rest, len, usageKey, usageKey.count) != nil, memmem(rest, len, assistantKey, assistantKey.count) != nil,
               let call = call(in: rest, count: len) {
                if var known = calls[call.key] {
                    known.t = min(known.t, call.t)
                    known.tokens = known.tokens.raised(to: call.tokens)
                    calls[call.key] = known
                } else {
                    calls[call.key] = call
                }
            }
            pos += len + 1
        }
    }

    /// Test and one-shot convenience.
    static func parse(_ data: Data) -> [ParsedCall] {
        var calls: [CallKey: ParsedCall] = [:]
        data.withUnsafeBytes { parse($0, into: &calls) }
        return calls.values.sorted { $0.t < $1.t }
    }

    private static func call(in p: UnsafeRawPointer, count: Int) -> ParsedCall? {
        let line = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: p), count: count, deallocator: .none)
        guard let e = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], e["type"] as? String == "assistant",
              let m = e["message"] as? [String: Any], let u = m["usage"] as? [String: Any],
              let model = m["model"] as? String, model.lowercased().contains("claude"), // drops <synthetic> and other providers' models
              let stamp = e["timestamp"] as? String, let t = epoch(iso: stamp),
              let id = (m["id"] as? String) ?? (e["uuid"] as? String) else { return nil }
        var tokens = TokenCounts()
        tokens.input = int(u["input_tokens"])
        tokens.output = int(u["output_tokens"])
        tokens.cacheRead = int(u["cache_read_input_tokens"])
        // The 5-minute / 1-hour split prices a cache write; a write without one is priced as 1 hour (what a subscription uses).
        let written = int(u["cache_creation_input_tokens"])
        let split = u["cache_creation"] as? [String: Any]
        let five = int(split?["ephemeral_5m_input_tokens"])
        tokens.cacheWrite5m = five
        tokens.cacheWrite1h = max(int(split?["ephemeral_1h_input_tokens"]), written - five)
        return ParsedCall(key: CallKey(id), t: t, model: model, tokens: tokens)
    }

    private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    // MARK: Time

    /// "2026-10-21T17:23:13.123Z" -> seconds since 1970, by hand: this runs once per usage line, up to ~100k lines on a first scan.
    static func epoch(iso s: String) -> Double? {
        let b = Array(s.utf8)
        func digits(_ from: Int, _ n: Int) -> Int? {
            guard from + n <= b.count else { return nil }
            var v = 0
            for i in from..<(from + n) {
                let d = Int(b[i]) - 48
                guard (0...9).contains(d) else { return nil }
                v = v * 10 + d
            }
            return v
        }
        guard b.count >= 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58, b[b.count - 1] == 90,
              let y = digits(0, 4), let mo = digits(5, 2), let d = digits(8, 2),
              let h = digits(11, 2), let mi = digits(14, 2), let sec = digits(17, 2) else { return slowEpoch(s) }
        var fraction = 0.0
        if b.count > 20 {
            guard b[19] == 46 else { return slowEpoch(s) }
            var scale = 0.1
            for i in 20..<(b.count - 1) {
                let dg = Int(b[i]) - 48
                guard (0...9).contains(dg) else { return slowEpoch(s) }
                fraction += Double(dg) * scale
                scale /= 10
            }
        }
        return Double(daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec) + fraction
    }

    /// Any other ISO 8601 shape (an offset instead of Z, say).
    private static func slowEpoch(_ s: String) -> Double? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d.timeIntervalSince1970 }
        return ISO8601DateFormatter().date(from: s)?.timeIntervalSince1970
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's algorithm).
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

/// Reads the part of one transcript nobody has read yet.
enum TranscriptScanner {
    struct Job: Sendable {
        var path: String
        /// Where the last scan stopped; 0 for a file never seen.
        var offset: Int
        /// Fingerprint of the file's first `headLength` bytes when it was last read; "" when it was not.
        var head = ""
        var headLength = 0
    }

    struct Output: Sendable {
        var path: String
        var calls: [ParsedCall]
        /// First byte not read: the start of a line still being written, or the end of the file.
        var consumed: Int
        /// Size of the file when it was read.
        var size: Int
        var head = ""
        var headLength = 0
        var failed = false
    }

    private static let block = 4 << 20
    /// A transcript only ever grows at its end, so if its first bytes are not what they were, it is a different file.
    private static let headBytes = 1024

    /// Reads in blocks (never maps the file: a transcript truncated under a mapping would crash the app) and stops before an
    /// unfinished last line, so the next scan starts exactly there. It resumes at `job.offset` only if the file is still the one that was
    /// read: long enough, and the same at its start. A file that is anything else (replaced, truncated, rewritten to the same size or more,
    /// or a saved offset that makes no sense) is read from the top; the calls already counted add nothing.
    static func scan(_ job: Job) -> Output {
        guard let handle = FileHandle(forReadingAtPath: job.path) else { return Output(path: job.path, calls: [], consumed: job.offset, size: 0, failed: true) }
        defer { try? handle.close() }
        do {
            let size = Int(try handle.seekToEnd())
            var consumed = 0
            var head = job.head, headLength = job.headLength
            if job.offset > 0, job.offset <= size, try startMatches(handle, job) {
                consumed = job.offset
            } else {
                (head, headLength) = try fingerprint(handle, size)
            }
            try handle.seek(toOffset: UInt64(consumed))
            var found: [CallKey: ParsedCall] = [:]
            var carry = Data()
            while let chunk = try handle.read(upToCount: block), !chunk.isEmpty {
                carry.append(chunk)
                guard let last = carry.lastIndex(of: 0x0A) else { continue } // one very long line: keep reading
                let end = last - carry.startIndex + 1
                carry.withUnsafeBytes { TranscriptParser.parse(UnsafeRawBufferPointer(rebasing: $0[0..<end]), into: &found) }
                consumed += end
                carry = Data(carry.dropFirst(end))
            }
            return Output(path: job.path, calls: Array(found.values), consumed: consumed, size: size, head: head, headLength: headLength)
        } catch {
            return Output(path: job.path, calls: [], consumed: job.offset, size: 0, failed: true)
        }
    }

    private static func startMatches(_ handle: FileHandle, _ job: Job) throws -> Bool {
        guard job.headLength > 0 else { return false }
        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: job.headLength), head.count == job.headLength else { return false }
        return hash(head) == job.head
    }

    private static func fingerprint(_ handle: FileHandle, _ size: Int) throws -> (head: String, length: Int) {
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: min(size, headBytes)) ?? Data()
        return (hash(head), head.count)
    }

    /// FNV-1a, as hex.
    private static func hash(_ data: Data) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { h = (h ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(h, radix: 16)
    }
}
