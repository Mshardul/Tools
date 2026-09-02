import Foundation

// Every sync mutation bumps `revision` and emits the matching QueueEvent.
extension DownloadEngine {
    func markRunning(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.state = .running
        job.startedAt = .now
        job.progress = nil
        job.sizeBytes = nil
        bump()
        emitSnapshot()
        logEvent(.jobStartedByScheduler(id: id, running: runningCount(), cap: cap))
    }

    func markProbing(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.state = .probing
        bump()
        emitSnapshot()
    }

    func recordProbeResult(_ id: UUID, _ result: Result<MediaMetadata, MetadataError>) {
        probeInFlight = false
        probeTask = nil
        guard let job = jobs.first(where: { $0.id == id }) else {
            evaluateSchedule()
            return
        }
        switch result {
        case let .success(meta):
            job.title = meta.title
            job.extractor = meta.extractor
            job.durationSeconds = meta.durationSeconds
            job.state = .queued
        case .failure(.launchFailed):
            haltForDepMissing(offending: job)
            return
        case let .failure(error):
            job.state = .failed(Self.errorClass(for: error))
            job.finishedAt = .now
        }
        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    func recordProgress(_ id: UUID, _ progress: Progress) {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .running else { return }
        job.progress = progress
        if job.sizeBytes == nil, let total = progress.totalBytes {
            job.sizeBytes = total
        }
        bump()
        emitProgress([id: progress])
    }

    func recordOutputPath(_ id: UUID, _ url: URL) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard !job.capturedOutputPaths.contains(url) else { return }
        job.capturedOutputPaths.append(url)
    }

    func recordExit(
        _ id: UUID,
        _ result: ProcessResult,
        integrity: IntegrityResult?,
        lastError: ErrorClass?,
        launchFailed: Bool,
        cookiesRequested: Bool = false,
        extractedZeroCookies: Bool = false
    ) {
        childTasks[id] = nil
        guard let job = jobs.first(where: { $0.id == id }) else {
            evaluateSchedule()
            return
        }
        // pause() / forceStart() eviction already moved the job off .running and SIGTERMed
        // its child — that exit is expected noise, not a terminal transition.
        guard job.state == .running else {
            evaluateSchedule()
            return
        }
        if launchFailed {
            haltForDepMissing(offending: job)
            return
        }
        if result.wasCancelled {
            job.state = .cancelled
            job.finishedAt = .now
            finishTerminal()
            return
        }

        if result.exitCode == 0 {
            job.actualQuality = integrity?.actualQuality
            switch integrity?.verdict {
            case .passed, .skipped, nil:
                job.integrityVerdict = integrity?.verdict
                job.outputFiles = finalizedOutputFiles(for: job)
                job.state = .completed
                job.finishedAt = .now
                finishTerminal()
                return
            case .failed:
                job.integrityVerdict = integrity?.verdict
            }
        }

        let errorClass = classifiedFailure(
            result: result,
            lastError: lastError,
            cookiesRequested: cookiesRequested,
            extractedZeroCookies: extractedZeroCookies
        )
        if errorClass.isAutoRetryable, job.attempt < preferences.maxAutoRetries {
            reQueueForBackoff(job, id: id, errorClass: errorClass)
            return
        }

        job.state = .failed(errorClass)
        job.finishedAt = .now
        finishTerminal()
    }

    // A user-requested cookie read that yielded nothing and then failed downstream is the
    // cookie problem, not whatever the download hit next (the Chrome app-bound case).
    private func classifiedFailure(
        result: ProcessResult,
        lastError: ErrorClass?,
        cookiesRequested: Bool,
        extractedZeroCookies: Bool
    ) -> ErrorClass {
        if result.exitCode != 0, cookiesRequested, extractedZeroCookies {
            return .cookieReadFailed
        }
        return classifyExit(result: result, lastError: lastError)
    }

    private func classifyExit(result: ProcessResult, lastError: ErrorClass?) -> ErrorClass {
        if result.exitCode == 0 {
            return .incomplete
        }
        return lastError ?? .unknown(raw: "yt-dlp exited \(result.exitCode)")
    }

    // .running -> .queued with attempt bumped and a pending deferral — one sync mutation,
    // no transient .failed snapshot. nextDownloads skips deferredIDs until the backoff fires.
    private func reQueueForBackoff(_ job: DownloadJob, id: UUID, errorClass: ErrorClass) {
        job.attempt += 1
        job.state = .queued
        job.progress = nil
        let deadline = dependencies.clock.now.addingTimeInterval(
            Backoff.delay(
                attempt: job.attempt,
                retryAfter: errorClass.retryAfterSeconds,
                tuning: dependencies.tuning
            )
        )
        bump()
        emitSnapshot()
        logEvent(.jobDeferred(id: id, until: deadline, reason: .backoff(attempt: job.attempt)))
        deferStart(id, until: deadline)
        evaluateSchedule()
    }

    func finishTerminal() {
        enforceTerminalCap()
        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    // A spawn/probe that fails to exec the binary is systemic, not the job's fault:
    // the job waits with the rest and the scheduler stops until revalidate() clears it.
    func haltForDepMissing(offending job: DownloadJob) {
        job.state = .queued
        job.progress = nil
        job.startedAt = nil
        queueHalt = .depMissing
        bump()
        emitSnapshot()
    }

    func markCancelled(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.state = .cancelled
        job.finishedAt = .now
        enforceTerminalCap()
        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    // In-memory terminal jobs, history.json, and JobLog files evict the same 200 by finishedAt.
    func enforceTerminalCap(limit: Int = 200) {
        let terminal = jobs
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        guard terminal.count > limit else { return }
        let dropped = terminal.dropFirst(limit)
        let droppedIDs = Set(dropped.map(\.id))
        jobs.removeAll { droppedIDs.contains($0.id) }
        for job in dropped {
            JobLog.delete(id: job.id, dir: dependencies.jobLogDir)
        }
    }
}
