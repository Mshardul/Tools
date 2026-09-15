import Foundation

public extension DownloadEngine {
    // "Restart" (UI) always restarts clean: attempt = 0, full auto-retry budget, re-enqueued at the tail, no deferral.
    func retry(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }), canRestart(job.state) else {
            return
        }

        job.state = .queued
        job.finishedAt = nil
        job.progress = nil
        job.sizeBytes = nil
        job.integrityVerdict = nil
        job.actualQuality = nil
        job.attempt = 0
        deletePartFiles(for: job)
        move(job, toTail: true)
        logEvent(.jobRetried(id: id))

        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    private func canRestart(_ state: JobState) -> Bool {
        switch state {
        case .cancelled:
            true
        case let .failed(errorClass):
            errorClass.presentation.offeredActions.contains(.retry)
        default:
            false
        }
    }

    // Forces browser cookies onto a from-scratch retry; forceCookies sticks for the job's life so a re-fail keeps them.
    func retryWithCookies(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }),
              case let .failed(errorClass) = job.state,
              errorClass.presentation.offeredActions.contains(.retryWithCookies)
        else {
            return
        }

        job.forceCookies = true
        job.attempt = 0
        job.state = .queued
        job.finishedAt = nil
        job.progress = nil
        job.sizeBytes = nil
        job.integrityVerdict = nil
        job.actualQuality = nil
        deletePartFiles(for: job)
        move(job, toTail: true)
        logEvent(.jobRetried(id: id))

        bump()
        emitSnapshot()
        evaluateSchedule()
    }
}
