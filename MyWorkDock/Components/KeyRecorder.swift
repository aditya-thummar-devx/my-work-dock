import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Renders a key combination with keyboard keycap badges, and handles interactive capture when editing.
struct KeyRecorder: View {
    let action: ShortcutAction
    let store: ShortcutStore
    @Binding var recordingAction: ShortcutAction?
    var locked: Bool = false

    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var validationWarning: String?
    @State private var eventMonitor: Any?
    @Environment(\.tokens) private var t

    private var isRecording: Bool {
        recordingAction == action
    }

    private var combo: KeyCombo {
        store.combo(for: action)
    }

    private var isFailed: Bool {
        store.failedActions.contains(action)
    }

    var body: some View {
        HStack(spacing: 6) {
            if isRecording {
                recordingView
            } else {
                normalView
            }
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    // MARK: - Normal View

    private var normalView: some View {
        HStack(spacing: 6) {
            if isFailed {
                HStack(spacing: 4) {
                    Icon(.warning, size: 12)
                    Text("In use")
                        .font(Typo.ui(11, .medium))
                }
                .foregroundStyle(Fixed.danger)
                .help("This combination could not be registered because another app already owns it.")
            }

            Button {
                guard !locked else { return }
                startRecording()
            } label: {
                HStack(spacing: 3) {
                    ForEach(combo.modifierSymbols, id: \.self) { sym in
                        keyCap(sym)
                    }
                    keyCap(KeyCombo.keyName(for: combo.keyCode))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .help("Click to change shortcut")

            Button {
                guard !locked else { return }
                startRecording()
            } label: {
                Text("Edit")
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(locked ? t.muted : t.text2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(t.ctrl))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityLabel("Edit \(action.label) shortcut")

            if store.isCustomized(action) {
                Button {
                    store.resetToDefault(action)
                } label: {
                    Icon(.refresh, size: 12)
                        .foregroundStyle(t.muted)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 4).fill(t.ctrl))
                }
                .buttonStyle(.plain)
                .help("Reset to default (\(action.defaultCombo.displayString))")
                .accessibilityLabel("Reset \(action.label) shortcut to default")
            }
        }
        .opacity(locked ? 0.45 : 1)
    }

    // MARK: - Recording View

    private var recordingView: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                let symbols = modifierSymbols(from: heldModifiers)
                if !symbols.isEmpty {
                    ForEach(symbols, id: \.self) { sym in
                        keyCap(sym, highlighted: true)
                    }
                    Text("…")
                        .font(Typo.mono(11))
                        .foregroundStyle(t.accent)
                } else if let warning = validationWarning {
                    Text(warning)
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Fixed.danger)
                } else {
                    Text("Press keys…")
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(t.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(t.inset))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(t.accent, lineWidth: 1.5))

            Button {
                stopRecording()
            } label: {
                Text("Cancel")
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(t.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(t.ctrl))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel editing shortcut")
        }
    }

    // MARK: - Keycap View

    private func keyCap(_ text: String, highlighted: Bool = false) -> some View {
        Text(text)
            .font(Typo.mono(11))
            .foregroundStyle(highlighted ? t.accent : t.text)
            .padding(.horizontal, 5)
            .frame(minWidth: 18)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(highlighted ? t.inset : t.ctrl))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(highlighted ? t.accent : t.border, lineWidth: 1))
    }

    private func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    // MARK: - Event Monitoring

    private func startRecording() {
        validationWarning = nil
        heldModifiers = []
        recordingAction = action
        stopMonitoring()

        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                DispatchQueue.main.async {
                    self.heldModifiers = flags
                }
                return event
            }

            if event.type == .keyDown {
                // Escape cancels recording
                if event.keyCode == 53 {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                    return nil
                }

                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let hasModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)

                guard hasModifier else {
                    DispatchQueue.main.async {
                        self.validationWarning = "Include ⌘, ⌥, or ⌃"
                    }
                    return nil
                }

                let newCombo = KeyCombo(keyCode: event.keyCode, modifiers: flags)
                DispatchQueue.main.async {
                    // Check if another action had this combo and clear or swap it
                    if let conflict = self.store.conflictingAction(for: newCombo, excluding: self.action) {
                        self.store.resetToDefault(conflict)
                    }
                    self.store.setCombo(newCombo, for: self.action)
                    self.stopRecording()
                }
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        recordingAction = nil
        heldModifiers = []
        validationWarning = nil
        stopMonitoring()
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
