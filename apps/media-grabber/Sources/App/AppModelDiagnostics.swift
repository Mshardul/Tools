import Foundation
import GrabberKit

extension AppModel {
    func restartShield() async {
        await engine.restartShield()
    }

    func restartYtDlp() async {
        healthController.markBusy(chipID: "engine")
        _ = await ytDlpUpdater.reinstallToMinimum()
        let report = await envProbe.probe()
        setLatestEnvironmentReport(report)
        let snapshot = await engine.currentSnapshot()
        healthController.update(snapshot: snapshot, now: .now, environmentReport: report)
        healthController.clearBusy(chipID: "engine")
    }
}
