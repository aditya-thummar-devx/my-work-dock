import Foundation
import Sparkle

/// OTA updates via Sparkle: checks daily, prompts the user to review and install, and asks before relaunching.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private let isIdle: () -> Bool
    private let closePanel: () -> Void
    private var controller: SPUStandardUpdaterController!

    init(isIdle: @escaping () -> Bool, closePanel: @escaping () -> Void = {}, automaticallyChecksForUpdates: Bool = true) {
        self.isIdle = isIdle
        self.closePanel = closePanel
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        updater.automaticallyDownloadsUpdates = false
        updater.updateCheckInterval = 86400
        controller.startUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Menu item: shows Sparkle's own window (up to date / error / release notes).
    func checkForUpdates() { controller.checkForUpdates(nil) }

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            self.closePanel()
        }
    }

    // MARK: - SPUUpdaterDelegate

    /// Sparkle will not install quietly in the background; user is always asked.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock install: @escaping () -> Void) -> Bool {
        false
    }

    /// Delay relaunch until the dock is idle (no ongoing terminal run, sign-in, etc.) when the user confirms install.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard !isIdle() else { return false }
        Task { @MainActor in
            while !isIdle() { try? await Task.sleep(for: .seconds(5)) }
            installHandler()
        }
        return true
    }
}
