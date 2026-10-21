import Foundation

/// What a running command printed, as plain text for the run sheet: ANSI colour and cursor codes dropped, `\r` rewrites
/// the current line (progress bars), and only the last `maxLines` lines are kept.
struct OutputBuffer: Equatable {
    static let maxLines = 2000

    /// The last element is the line still being written.
    private(set) var lines: [String] = [""]
    private var mode = Mode.text
    private var rewrite = false
    /// Tail of a chunk that ended inside a multi-byte character.
    private var pending = Data()

    private enum Mode { case text, escape, csi, osc }

    var text: String { lines.joined(separator: "\n") }
    var isEmpty: Bool { lines == [""] }

    mutating func append(_ data: Data) {
        var bytes = pending + data
        pending = Data()
        // Hold back up to 3 trailing bytes of a character the next chunk completes.
        var keep = 0
        while keep <= 3, keep <= bytes.count, String(data: bytes.dropLast(keep), encoding: .utf8) == nil { keep += 1 }
        if keep <= 3, keep <= bytes.count {
            pending = Data(bytes.suffix(keep))
            bytes = Data(bytes.dropLast(keep))
        }
        append(String(decoding: bytes, as: UTF8.self))
    }

    mutating func append(_ string: String) {
        for scalar in string.unicodeScalars {
            switch mode {
            case .text: text(scalar)
            case .escape:
                mode = scalar == "[" ? .csi : scalar == "]" ? .osc : .text
            case .csi:
                if (0x40...0x7E).contains(scalar.value) { mode = .text }
            case .osc:
                if scalar.value == 0x07 { mode = .text } else if scalar.value == 0x1B { mode = .escape }
            }
        }
    }

    private mutating func text(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "\u{1B}": mode = .escape
        case "\n":
            rewrite = false
            lines.append("")
            if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        case "\r": rewrite = true
        case "\t": put("    ")
        default:
            if scalar.value >= 0x20 && scalar.value != 0x7F { put(String(scalar)) }
        }
    }

    private mutating func put(_ s: String) {
        if rewrite {
            lines[lines.count - 1] = ""
            rewrite = false
        }
        lines[lines.count - 1] += s
    }
}
