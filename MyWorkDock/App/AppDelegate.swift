import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerAll()
        // Unit tests host the app but must not create the panel.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #if DEBUG
        if let code = MainActor.assumeIsolated({ SnapshotRunner.runIfRequested() }) { exit(code) }
        #endif

        let model = NotchModel()
        #if DEBUG
        MainActor.assumeIsolated { SnapshotRunner.applyStartState(to: model) }
        #endif
        MainActor.assumeIsolated {
            model.emulator.startMonitoring()
            Task { await model.claudex.refresh() }
        }
        // No automatic login item: "Open at login" in the right-click menu is the only way to turn it on.
        let controller = NotchWindowController(model: model)
        self.controller = controller
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak controller] in
            controller?.model.togglePanel()
        }
    }
}
