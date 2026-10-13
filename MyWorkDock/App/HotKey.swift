import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
final class HotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var handlerInstalled = false
    private static var live: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    /// Returns nil if another app already owns the combination.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        Self.installHandler()
        let id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D57_4B44), id: id) // 'MWKD'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            NSLog("MyWorkDock: hotkey registration failed (OSStatus %d)", status)
            return nil
        }
        Self.live[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKey.live[id.id]?.action() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
