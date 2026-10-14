import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var hotKey: HotKey?
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
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak controller] in
            controller?.model.togglePanel()
        }
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
