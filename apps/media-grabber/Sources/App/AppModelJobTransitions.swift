import Foundation
import GrabberKit

extension AppModel {
    func handleJobTransitions(
        _ snapshot: QueueSnapshot,
        previousStates: [UUID: JobState]
    ) {
        for job in snapshot.jobs {
            guard let previous = previousStates[job.id], previous != job.state else { continue }
            switch job.state {
            case .completed:
                handleJobCompleted(job)
            case let .failed(errorClass):
                handleJobFailed(job, errorClass: errorClass)
            default:
                break
            }
        }
    }

    private func handleJobCompleted(_ job: JobSnapshot) {
        guard isAppActive() else { return }
        let title = job.title ?? job.url
        toastCenter.enqueue(ToastItem(
            text: "\(title) saved",
            actionTitle: "Reveal",
            action: { [revealSink] in
                await MainActor.run { revealSink.reveal(job.outputFiles) }
            }
        ))
    }

    private func handleJobFailed(_ job: JobSnapshot, errorClass: ErrorClass) {
        guard !isAppActive() else { return }
        let title = job.title ?? job.url
        Task { [notificationRouter] in
            await notificationRouter.notifyJobFailed(
                title: title,
                reason: errorClass.presentation.sentence
            )
        }
    }
}
