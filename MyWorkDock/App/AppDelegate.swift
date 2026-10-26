import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var hotKeyManager: HotKeyManager?
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
        // Debug builds are never updated: they would fetch release builds over themselves.
        #if !DEBUG
        MainActor.assumeIsolated {
            let updater = Updater(isIdle: { [unowned model] in model.isIdle },
                                  closePanel: { [unowned model] in model.closePanel() },
                                  automaticallyChecksForUpdates: model.autoCheckUpdates)
            model.onAutoCheckUpdates = { [unowned updater] on in
                updater.automaticallyChecksForUpdates = on
            }
            // Sparkle's window is a normal-level window and the open panel floats above it (and never closes on outside clicks), so close it first.
            model.checkForUpdates = { [unowned model] in
                model.closePanel()
                updater.checkForUpdates()
            }
        }
        #endif
        // No automatic login item: "Open at login" in the right-click menu is the only way to turn it on.
        let controller = NotchWindowController(model: model)
        self.controller = controller
        let hotKeyManager = HotKeyManager(model: model, controller: controller)
        self.hotKeyManager = hotKeyManager
        model.onShortcutsChange = { [weak hotKeyManager] in
            hotKeyManager?.sync()
        }
        addStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { controller?.model.openPanel() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { controller?.model.runner.killNow() }
    }

    private func addStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        item.button?.image = icon
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide MyWorkDock", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Usage Guide…", action: #selector(openUsageGuide), keyEquivalent: "").target = self
        #if !DEBUG
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MyWorkDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { MainActor.assumeIsolated { controller?.model.togglePanel() } }
    @objc private func openUsageGuide() { MainActor.assumeIsolated { controller?.model.openUsageGuide() } }
    @objc private func checkForUpdates() { MainActor.assumeIsolated { controller?.model.checkForUpdates?() } }
}
