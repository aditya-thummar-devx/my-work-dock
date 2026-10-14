import Foundation
import Sparkle

/// OTA updates via Sparkle: checks hourly, downloads quietly, then relaunches into the new build once `isIdle`.
/// A menu-bar app rarely quits, so Sparkle's default "install on quit" would leave updates staged for weeks.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private let isIdle: () -> Bool
    private var controller: SPUStandardUpdaterController!

    init(isIdle: @escaping () -> Bool) {
        self.isIdle = isIdle
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        // Set in code, not Info.plist: also skips Sparkle's "check automatically?" prompt on the second launch.
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
        updater.updateCheckInterval = 3600
        controller.startUpdater()
    }

    /// Menu item: unlike the scheduled checks, this one shows Sparkle's own window (up to date / error / release notes).
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// The update is downloaded and staged; install it as soon as nothing would be interrupted. Quitting first installs it too.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock install: @escaping () -> Void) -> Bool {
        Task { @MainActor in
            while !isIdle() { try? await Task.sleep(for: .seconds(30)) }
            install()
        }
        return true
    }
}
