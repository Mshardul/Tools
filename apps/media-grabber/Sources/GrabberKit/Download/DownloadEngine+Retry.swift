import Foundation

public extension DownloadEngine {
    // "Restart" (UI) always restarts clean: attempt = 0, full auto-retry budget, re-enqueued at the tail, no deferral.
    func retry(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }), canRestart(job.state) else {
            return
        }

        restartFromScratch(job)
    }

    private func restartFromScratch(_ job: DownloadJob) {
        job.attempt = 0
        job.burnedPlayerClients = []
        job.state = .queued
        job.finishedAt = nil
        job.progress = nil
        job.sizeBytes = nil
        job.integrityVerdict = nil
        job.actualQuality = nil
        deletePartFiles(for: job)
        move(job, toTail: true)
        logEvent(.jobRetried(id: job.id))

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

    // Restarts a sign-in-fixable failure from scratch once the user has chosen a browser.
    func retryWithCookies(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }),
              case let .failed(errorClass) = job.state,
              SignInPolicy.fixableBySignIn(errorClass, host: RateHost(urlString: job.request.url))
        else {
            return
        }

        restartFromScratch(job)
    }

    func setPasscode(_ passcode: String, for url: String) async {
        passcodes[url] = passcode
    }

    // Restarts a passcode failure from scratch with the passcode the user just typed; any other job is left alone.
    func retryWithPasscode(_ id: UUID, passcode: String) async {
        guard let job = jobs.first(where: { $0.id == id }),
              case let .failed(errorClass) = job.state,
              errorClass == .passcodeRequired || errorClass == .passcodeRejected
        else {
            return
        }

        job.videoPassword = passcode
        restartFromScratch(job)
    }
}

extension DownloadEngine {
    func dropPasscode(for job: DownloadJob) {
        job.videoPassword = nil
    }
}
