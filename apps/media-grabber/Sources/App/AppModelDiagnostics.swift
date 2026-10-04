import Foundation
import GrabberKit

extension AppModel {
    func restartShield() async {
        let succeeded = await engine.restartShield()
        if !succeeded {
            toastCenter.enqueue(ToastItem(
                text: "Bot-check shield restart failed",
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
        if case let .failure(reason) = result {
            toastCenter.enqueue(ToastItem(
                text: "yt-dlp update failed: \(reason)",
                actionTitle: nil,
                action: nil
            ))
        }
    }
}
