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
        // A job already off .running was evicted by pause()/forceStart(); its child's exit is expected noise.
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
        if result.exitCode == 0, completeIfClean(job, integrity: integrity) {
            return
        }

        let errorClass = classifiedFailure(
            result: result,
            lastError: lastError,
            cookiesRequested: cookiesRequested,
            extractedZeroCookies: extractedZeroCookies
        )
        routeFailure(job, id: id, errorClass: errorClass)
    }

    private func completeIfClean(_ job: DownloadJob, integrity: IntegrityResult?) -> Bool {
        job.actualQuality = integrity?.actualQuality
        job.integrityVerdict = integrity?.verdict
        if case .failed = integrity?.verdict {
            return false
        }
        job.outputFiles = finalizedOutputFiles(for: job)
        job.state = .completed
        job.finishedAt = .now
        recordCleanSuccessFor(job)
        finishTerminal()
        return true
    }

    private func routeFailure(_ job: DownloadJob, id: UUID, errorClass: ErrorClass) {
        let host = RateHost(urlString: job.request.url)
        strikeHostIfRateLimited(errorClass, host: host)

        if errorClass.isAutoRetryable, job.attempt < preferences.maxAutoRetries {
            if case .rateLimited = errorClass {
                reQueueForHostRate(job, id: id, host: host)
            } else {
                reQueueForBackoff(job, id: id, errorClass: errorClass)
            }
            return
        }
        job.state = .failed(errorClass)
        job.finishedAt = .now
        finishTerminal()
    }

    private func recordCleanSuccessFor(_ job: DownloadJob) {
        let before = rateLimiter.adaptiveCap
        rateLimiter.recordCleanSuccess(
            host: RateHost(urlString: job.request.url), now: dependencies.clock.now
        )
        if rateLimiter.adaptiveCap != before {
            logEvent(.adaptiveConcurrencyChanged(
                from: before, to: rateLimiter.adaptiveCap, reason: "clean_streak"
            ))
        }
    }

    // The strike is about the host — Step A, unconditional on a rate-limited exit, terminal or not.
    private func strikeHostIfRateLimited(_ errorClass: ErrorClass, host: RateHost) {
        guard case let .rateLimited(retryAfter) = errorClass else { return }
        let before = rateLimiter.adaptiveCap
        let fromState = describeRateState(rateLimiter.state(for: host))
        rateLimiter.recordStrike(
            host: host, retryAfter: retryAfter,
            lastErrorKey: errorClass.key, now: dependencies.clock.now
        )
        let toState = rateLimiter.state(for: host)
        logEvent(.hostRateStateChanged(
            host: host.canonical, from: fromState, to: describeRateState(toState)
        ))
        if case let .circuitOpen(_, strikes) = toState {
            logEvent(.circuitOpened(host: host.canonical, strikes: strikes))
        }
        if rateLimiter.adaptiveCap != before {
            logEvent(.adaptiveConcurrencyChanged(
                from: before, to: rateLimiter.adaptiveCap, reason: "throttle"
            ))
        }
    }

    // At most one .cooldown job per host — the rest wait .queued, gated by blockedHostIDs.
    private func reQueueForHostRate(_ job: DownloadJob, id: UUID, host: RateHost) {
        job.attempt += 1
        job.progress = nil
        let siblingCooling = jobs.contains {
            $0.id != id && isCooldownState($0.state)
                && RateHost(urlString: $0.request.url) == host
        }
        if let deadline = rateLimiter.cooldownDeadline(for: host), !siblingCooling {
            job.state = .cooldown(until: deadline)
            job.cooldownUntil = deadline
            logEvent(.jobDeferred(
                id: id, until: deadline,
                reason: .hostCooldown(
                    host: host.canonical, strikes: rateLimiter.state(for: host).strikes
                )
            ))
            deferStart(id, until: deadline)
        } else {
            job.state = .queued
            job.cooldownUntil = nil
            cancelDeferral(id)
        }
        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    func isCooldownState(_ state: JobState) -> Bool {
        if case .cooldown = state {
            return true
        }
        return false
    }

    private func describeRateState(_ state: RateState) -> String {
        switch state {
        case .normal: "normal"
        case .cooldown: "cooldown"
        case .circuitOpen: "circuit_open"
        }
    }

    // A cookie read that yielded nothing then failed downstream is the cookie problem (the Chrome app-bound case).
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

    // One sync .running -> .queued with a pending deferral, so no transient .failed snapshot leaks.
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
        job.cooldownUntil = deadline
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

    // A failure to exec the binary is systemic: the job re-queues and the scheduler stops until revalidate() clears it.
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
