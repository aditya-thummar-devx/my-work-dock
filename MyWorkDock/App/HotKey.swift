import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
final class HotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private let id: UInt32
    private static var handlerInstalled = false
    private static var live: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    /// Returns nil if another app already owns the combination.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        Self.installHandler()
        let id = Self.nextID
        Self.nextID += 1
        self.id = id
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D57_4B44), id: id) // 'MWKD'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            NSLog("MyWorkDock: hotkey registration failed (OSStatus %d)", status)
            return nil
        }
        Self.live[id] = action
    }

    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        Self.live.removeValue(forKey: id)
    }

    deinit {
        unregister()
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKey.live[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Coordinates registered Carbon hotkeys with ShortcutStore configuration and NotchModel actions.
@MainActor
final class HotKeyManager {
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    private weak var controller: NotchWindowController?
    private weak var model: NotchModel?

    init(model: NotchModel, controller: NotchWindowController) {
        self.model = model
        self.controller = controller
        sync()
    }

    func sync() {
        for hotKey in hotKeys.values {
            hotKey.unregister()
        }
        hotKeys.removeAll()

        guard let model, let controller else { return }

        let store = model.shortcuts
        store.failedActions.removeAll()

        guard store.masterEnabled else { return }

        for action in ShortcutAction.allCases {
            guard store.isActionSwitchedOn(action) else { continue }
            if isFeatureDisabled(action, model: model) { continue }

            let combo = store.combo(for: action)
            let handler = makeHandler(for: action, controller: controller)

            if let hotKey = HotKey(keyCode: Int(combo.keyCode), modifiers: combo.carbonModifiers, action: handler) {
                hotKeys[action] = hotKey
            } else {
                store.failedActions.insert(action)
            }
        }
    }

    deinit {
        for hotKey in hotKeys.values {
            hotKey.unregister()
        }
        hotKeys.removeAll()
    }

    private func isFeatureDisabled(_ action: ShortcutAction, model: NotchModel) -> Bool {
        switch action {
        case .togglePanel:
            return false
        case .clipboard:
            return model.disabled.contains(.clipboard)
        case .calendar:
            return model.disabled.contains(.calendar)
        case .claude:
            return model.disabled.contains(.claude)
        case .notesTodo:
            return model.disabled.contains(.notes) || model.disabledSubs.contains(.notesTodo)
        case .notesCommands:
            return model.disabled.contains(.notes) || model.disabledSubs.contains(.notesCommands)
        case .notesPrompts:
            return model.disabled.contains(.notes) || model.disabledSubs.contains(.notesPrompts)
        case .notesLinks:
            return model.disabled.contains(.notes) || model.disabledSubs.contains(.notesLinks)
        case .emulator:
            return model.disabled.contains(.emulator)
        case .claudex:
            return model.disabled.contains(.claudex)
        }
    }

    private func makeHandler(for action: ShortcutAction, controller: NotchWindowController) -> () -> Void {
        switch action {
        case .togglePanel:
            return { [weak controller] in controller?.model.togglePanel() }
        case .clipboard:
            return { [weak controller] in controller?.model.show(.clipboard) }
        case .calendar:
            return { [weak controller] in controller?.model.show(.calendar) }
        case .claude:
            return { [weak controller] in controller?.model.show(.claude) }
        case .notesTodo:
            return { [weak controller] in controller?.model.show(.notes, notes: .todo) }
        case .notesCommands:
            return { [weak controller] in controller?.model.show(.notes, notes: .commands) }
        case .notesPrompts:
            return { [weak controller] in controller?.model.show(.notes, notes: .prompts) }
        case .notesLinks:
            return { [weak controller] in controller?.model.show(.notes, notes: .links) }
        case .emulator:
            return { [weak controller] in controller?.model.show(.emulator) }
        case .claudex:
            return { [weak controller] in controller?.model.show(.claudex) }
        }
    }
}
