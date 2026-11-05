import Sparkle

@MainActor
final class SparkleAppUpdating: AppUpdating {
    private var controller: SPUStandardUpdaterController?

    func start(automaticChecks: Bool) {
        guard controller == nil else {
            setAutomaticChecks(automaticChecks)
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyDownloadsUpdates = false
        controller.updater.automaticallyChecksForUpdates = automaticChecks
        controller.startUpdater()
        self.controller = controller
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}
