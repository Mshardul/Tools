import Foundation
import GrabberKit

extension AppModel {
    func makeSignInTestProbe() -> (any MetadataProbing)? {
        guard let path = latestEnvironmentReport?.ytDlp?.path else { return nil }
        return CanaryProbe.makeProbe(ytDlpURL: path, runner: ProcessRunner())
    }

    func restartShield() async {
        let succeeded = await engine.restartShield()
        if !succeeded {
            toastCenter.enqueue(ToastItem(
                text: "Couldn't restart the YouTube check.",
                actionTitle: nil,
                action: nil
            ))
        }
    }

    func restartYtDlp() async {
        healthController.markBusy(chipID: "engine")
        let result = await ytDlpUpdater.reinstallToMinimum()
        let report = await envProbe.probe()
        setLatestEnvironmentReport(report)
        let snapshot = await engine.currentSnapshot()
        healthController.update(snapshot: snapshot, now: .now, environmentReport: report)
        healthController.clearBusy(chipID: "engine")
        if case .failure = result {
            toastCenter.enqueue(ToastItem(
                text: "Couldn't update the downloader.",
                actionTitle: nil,
                action: nil
            ))
        }
    }

    func cancelJob() async {
        guard let id = lastSubmittedJobID else { return }
        await engine.cancel(id)
    }

    func resetCircuit(host: RateHost) async {
        await engine.resetCircuit(host)
    }

    func resetAllCircuits() async {
        await engine.resetAllCircuits()
    }

    func resetAllSettings() {
        prefs.resetToDefaults()
    }
}
