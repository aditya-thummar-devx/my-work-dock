import Foundation

/// One ring in the right ear. `percent == nil` means the account has no reading.
struct PeekBar: Equatable, Identifiable {
    var label: String
    var percent: Int?
    /// Reset text without the leading ↻; nil renders "idle".
    var reset: String?

    var id: String { label }
    var isHot: Bool { (percent ?? 0) >= 80 }
}

struct PeekData: Equatable {
    var name: String
    /// POOL (a pool member is in use) or SSO (the active saved account).
    var isPool: Bool
    var bars: [PeekBar]

    var initial: String { String(name.prefix(1)).uppercased() }
}
