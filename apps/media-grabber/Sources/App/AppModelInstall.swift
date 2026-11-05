import AppKit
import Foundation
import GrabberKit

extension AppModel {
    func stopConsumer() {
        consumerTask?.cancel()
        consumerTask = nil
    }

    var canReplaceItself: Bool {
        InstallLocation.canReplaceItself(bundleURL: bundleURL, home: homeURL)
    }

    func startUpdaterIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard canReplaceItself else { return }
        appUpdating.start(automaticChecks: prefs.autoCheckAppUpdates)
    }

    func setAutomaticUpdateChecks(_ enabled: Bool) {
        appUpdating.setAutomaticChecks(enabled)
    }

    func checkForUpdates() {
        guard canReplaceItself else { return }
        startUpdaterIfNeeded()
        appUpdating.checkForUpdates()
    }

    func offerToMoveIntoApplicationsIfNeeded() async {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard bundleURL.lastPathComponent == "MediaGrabber.app", !canReplaceItself else { return }
        let confirmed = await confirm(ConfirmationRequest(
            title: InstallLocation.moveTitle,
            message: InstallLocation.moveMessage,
            confirmTitle: "Move",
            cancelTitle: "Not now"
        ))
        guard confirmed else { return }
        let destination = InstallLocation.destination(
            bundleURL: bundleURL,
            home: homeURL,
            systemApplicationsWritable: FileManager.default.isWritableFile(atPath: "/Applications")
        )
        do {
            try InstallLocation.move(bundleURL: bundleURL, to: destination)
        } catch InstallMoveError.destinationExists {
            _ = await notice(title: "Already in Applications", message: InstallLocation.alreadyThereMessage)
            return
        } catch {
            _ = await notice(title: "Couldn't move MediaGrabber", message: InstallLocation.moveFailedMessage)
            return
        }
        let executableName = Bundle.main.executableURL?.lastPathComponent ?? "MediaGrabber"
        let executable = destination
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        AppRelauncher().relaunch(executablePath: executable.path)
    }

    func uninstall() async {
        let snapshot = await engine.currentSnapshot()
        let titles = UninstallCopy.activeTitles(jobs: snapshot.jobs.map {
            UninstallJob(title: $0.title, url: $0.url, state: $0.state)
        })
        let confirmed = await confirm(ConfirmationRequest(
            title: UninstallCopy.confirmTitle,
            message: UninstallCopy.message(activeTitles: titles),
            confirmTitle: UninstallCopy.confirmButton,
            cancelTitle: "Cancel",
            isDestructive: true
        ))
        guard confirmed else { return }
        stopConsumer()
        let effects = LiveUninstallEffects(
            engine: engine,
            homeURL: homeURL,
            bundleURL: bundleURL,
            defaults: defaults
        )
        switch await UninstallSequence.run(effects) {
        case .removed:
            quitCoordinator.abandonWithoutSaving()
            NSApplication.shared.terminate(nil)
        case .needsManualRemoval:
            revealSink.reveal([bundleURL])
            _ = await notice(title: UninstallCopy.manualTitle, message: UninstallCopy.manualMessage)
        case .failed:
            _ = await notice(title: UninstallCopy.failedTitle, message: UninstallCopy.failedMessage)
        }
    }

    private func notice(title: String, message: String) async -> Bool {
        await confirm(ConfirmationRequest(
            title: title,
            message: message,
            confirmTitle: "OK",
            cancelTitle: nil
        ))
    }
}

private final class LiveUninstallEffects: UninstallEffects, @unchecked Sendable {
    private let engine: any DownloadEngineProtocol
    private let homeURL: URL
    private let bundleURL: URL
    private let defaults: UserDefaults

    init(
        engine: any DownloadEngineProtocol,
        homeURL: URL,
        bundleURL: URL,
        defaults: UserDefaults
    ) {
        self.engine = engine
        self.homeURL = homeURL
        self.bundleURL = bundleURL
        self.defaults = defaults
    }

    func shutdown() async {
        await engine.shutdown()
    }

    func deleteFootprint() throws {
        try AppFootprint.remove(in: homeURL)
    }

    func clearPreferences() {
        defaults.removePersistentDomain(forName: AppFootprint.preferenceDomain)
        UserDefaults.standard.removePersistentDomain(forName: AppFootprint.preferenceDomain)
    }

    func trashBundle() throws {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: bundleURL, resultingItemURL: &resulting)
    }
}
