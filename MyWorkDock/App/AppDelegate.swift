import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var hotKeys: [HotKey] = []
    private var statusItem: NSStatusItem?

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
        MainActor.assumeIsolated { model.startServices() }
        // No automatic login item: "Open at login" in the right-click menu is the only way to turn it on.
        let controller = NotchWindowController(model: model)
        self.controller = controller
        let cmdShift = cmdKey | shiftKey
        // A combo another app already owns gives nil and is skipped.
        let keys: [HotKey?] = [
            HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak controller] in controller?.model.togglePanel() },
            HotKey(keyCode: kVK_ANSI_P, modifiers: cmdShift) { [weak controller] in controller?.model.show(.notes, notes: .prompts) },
            HotKey(keyCode: kVK_ANSI_E, modifiers: cmdShift) { [weak controller] in controller?.model.show(.emulator) },
            HotKey(keyCode: kVK_ANSI_X, modifiers: cmdShift) { [weak controller] in controller?.model.show(.claudex) },
        ]
        hotKeys = keys.compactMap { $0 }
        addStatusItem()
    }

    private func addStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        item.button?.image = icon
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide MyWorkDock", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyWorkDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { MainActor.assumeIsolated { controller?.model.togglePanel() } }
}
