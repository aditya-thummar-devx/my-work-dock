import AppKit
import Carbon.HIToolbox
import Observation

/// Physical key and modifier combination for global hotkeys and internal dock shortcuts.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// NSEvent.ModifierFlags rawValue (.deviceIndependentFlagsMask)
    var modifiers: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    init(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = UInt16(keyCode)
        var flags: NSEvent.ModifierFlags = []
        if (carbonModifiers & cmdKey) != 0 { flags.insert(.command) }
        if (carbonModifiers & optionKey) != 0 { flags.insert(.option) }
        if (carbonModifiers & controlKey) != 0 { flags.insert(.control) }
        if (carbonModifiers & shiftKey) != 0 { flags.insert(.shift) }
        self.modifiers = flags.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    var carbonModifiers: Int {
        var mods = 0
        let flags = modifierFlags
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.shift) { mods |= shiftKey }
        return mods
    }

    /// List of modifier symbol strings in standard macOS order: Control, Option, Shift, Command.
    var modifierSymbols: [String] {
        var symbols: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    /// Formatted text representation, e.g. "⌥ Space", "⌘⇧V", "⌘⇧M".
    var displayString: String {
        let syms = modifierSymbols.joined()
        let name = KeyCombo.keyName(for: keyCode)
        if name.count > 1 {
            return syms.isEmpty ? name : "\(syms) \(name)"
        } else {
            return "\(syms)\(name)"
        }
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Fwd Del"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            if let translated = translate(keyCode: keyCode), !translated.isEmpty {
                return translated.uppercased()
            }
            return fallbackKeyName(for: keyCode)
        }
    }

    private static func translate(keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        guard let dataPtr = CFDataGetBytePtr(layout) else { return nil }
        let header = unsafeBitCast(dataPtr, to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var unicodeString = [UniChar](repeating: 0, count: 4)
        var actualStringLength: Int = 0

        let status = UCKeyTranslate(
            header,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &actualStringLength,
            &unicodeString
        )
        guard status == noErr, actualStringLength > 0 else { return nil }
        return String(utf16CodeUnits: unicodeString, count: actualStringLength)
    }

    private static func fallbackKeyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        default: return "Key \(keyCode)"
        }
    }
}

/// Category grouping for settings layout.
enum ShortcutCategory: String, CaseIterable, Identifiable {
    case general
    case tabs
    case notes

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: "General"
        case .tabs: "Menus & Tabs"
        case .notes: "Notes Tabs"
        }
    }
}

/// Every global shortcut-triggered action in MyWorkDock.
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case togglePanel
    case clipboard
    case calendar
    case notesTodo
    case notesCommands
    case notesPrompts
    case notesLinks
    case emulator
    case claudex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .togglePanel: "Open / close panel"
        case .clipboard: "Clipboard"
        case .calendar: "My Calendar"
        case .notesTodo: "Notes › TODO"
        case .notesCommands: "Notes › Commands"
        case .notesPrompts: "Notes › Prompts"
        case .notesLinks: "Notes › Links"
        case .emulator: "Emulator"
        case .claudex: "claudex"
        }
    }

    var glyph: Glyph {
        switch self {
        case .togglePanel: .power
        case .clipboard: .clipboard
        case .calendar: .calendar
        case .notesTodo, .notesCommands, .notesPrompts, .notesLinks: .notes
        case .emulator: .phone
        case .claudex: .gauge
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .togglePanel:
            return .general
        case .clipboard, .calendar, .emulator, .claudex:
            return .tabs
        case .notesTodo, .notesCommands, .notesPrompts, .notesLinks:
            return .notes
        }
    }

    var defaultCombo: KeyCombo {
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        switch self {
        case .togglePanel:
            return KeyCombo(keyCode: UInt16(kVK_Space), modifiers: .option)
        case .clipboard:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: cmdShift)
        case .calendar:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_M), modifiers: cmdShift)
        case .notesTodo:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_D), modifiers: cmdShift)
        case .notesCommands:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifiers: cmdShift)
        case .notesPrompts:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: cmdShift)
        case .notesLinks:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_L), modifiers: cmdShift)
        case .emulator:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: cmdShift)
        case .claudex:
            return KeyCombo(keyCode: UInt16(kVK_ANSI_X), modifiers: cmdShift)
        }
    }
}

/// Manages shortcut configuration, custom key assignments, and master/individual toggles.
@Observable
final class ShortcutStore {
    /// Master toggle: when false, all global hotkeys are released and disabled.
    var masterEnabled: Bool {
        didSet {
            defaults?.set(masterEnabled, forKey: "shortcutsMasterEnabled")
            onChange?()
        }
    }

    /// Set of individually disabled shortcut actions.
    var disabledActions: Set<ShortcutAction> {
        didSet {
            defaults?.set(disabledActions.map(\.rawValue).sorted(), forKey: "shortcutsDisabledActions")
            onChange?()
        }
    }

    /// User customized key combinations (missing actions use action.defaultCombo).
    var customBindings: [ShortcutAction: KeyCombo] {
        didSet {
            saveCustomBindings()
            onChange?()
        }
    }

    /// Actions that failed registration with Carbon (e.g. claimed by another system application).
    var failedActions: Set<ShortcutAction> = []

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored var onChange: (() -> Void)?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let defaults {
            if defaults.object(forKey: "shortcutsMasterEnabled") != nil {
                masterEnabled = defaults.bool(forKey: "shortcutsMasterEnabled")
            } else {
                masterEnabled = true
            }
            if let disabled = defaults.stringArray(forKey: "shortcutsDisabledActions") {
                disabledActions = Set(disabled.compactMap(ShortcutAction.init(rawValue:)))
            } else {
                disabledActions = []
            }
            if let data = defaults.data(forKey: "shortcutsCustomBindings"),
               let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
                var map: [ShortcutAction: KeyCombo] = [:]
                for (key, val) in decoded {
                    if let action = ShortcutAction(rawValue: key) {
                        map[action] = val
                    }
                }
                customBindings = map
            } else {
                customBindings = [:]
            }
        } else {
            masterEnabled = true
            disabledActions = []
            customBindings = [:]
        }
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        customBindings[action] ?? action.defaultCombo
    }

    func isEnabled(_ action: ShortcutAction) -> Bool {
        masterEnabled && !disabledActions.contains(action)
    }

    func isActionSwitchedOn(_ action: ShortcutAction) -> Bool {
        !disabledActions.contains(action)
    }

    func setActionSwitchedOn(_ action: ShortcutAction, _ on: Bool) {
        if on {
            disabledActions.remove(action)
        } else {
            disabledActions.insert(action)
        }
    }

    func setMasterEnabled(_ enabled: Bool) {
        masterEnabled = enabled
    }

    func setCombo(_ combo: KeyCombo, for action: ShortcutAction) {
        if combo == action.defaultCombo {
            customBindings.removeValue(forKey: action)
        } else {
            customBindings[action] = combo
        }
    }

    func resetToDefault(_ action: ShortcutAction) {
        customBindings.removeValue(forKey: action)
        disabledActions.remove(action)
    }

    func resetAll() {
        customBindings.removeAll()
        disabledActions.removeAll()
        masterEnabled = true
    }

    func isCustomized(_ action: ShortcutAction) -> Bool {
        customBindings[action] != nil
    }

    /// Checks if another registered action already uses this combination.
    func conflictingAction(for combo: KeyCombo, excluding: ShortcutAction) -> ShortcutAction? {
        for action in ShortcutAction.allCases where action != excluding {
            if self.combo(for: action) == combo {
                return action
            }
        }
        return nil
    }

    private func saveCustomBindings() {
        guard let defaults else { return }
        var stringMap: [String: KeyCombo] = [:]
        for (action, combo) in customBindings {
            stringMap[action.rawValue] = combo
        }
        if let data = try? JSONEncoder().encode(stringMap) {
            defaults.set(data, forKey: "shortcutsCustomBindings")
        }
    }
}
