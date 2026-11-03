import Foundation

extension DownloadEngine {
    // MARK: - Snapshot / emit

    func buildSnapshot() -> QueueSnapshot {
        let cookiesConfigured = !preferences.cookiesFromBrowser.isNone
        let jobSnapshots = jobs.map { job in
            let advice = Self.signInAdvice(for: job, cookiesConfigured: cookiesConfigured)
            return job.snapshot(
                availableActions: Self.availableActions(
                    for: job.state,
                    isImmediatelySchedulable: isImmediatelySchedulable(job),
                    signInAdvice: advice
                ),
                signInAdvice: advice
            )
        }
        return QueueSnapshot(
            jobs: jobSnapshots,
            revision: revision,
            queueHalt: effectiveQueueHalt(),
            generatedAt: .now,
            hostRateSummary: rateLimiter.displaySummary(now: dependencies.clock.now),
            isOnline: isOnline,
            shieldStatus: shieldStatus,
            playlistGroups: playlistGroupSnapshots(jobSnapshots: jobSnapshots)
        )
    }

    static func signInAdvice(for job: DownloadJob, cookiesConfigured: Bool) -> SignInAdvice {
        guard case let .failed(errorClass) = job.state else { return .none }
        return SignInPolicy.advice(
            for: errorClass,
            host: RateHost(urlString: job.request.url),
            cookiesConfigured: cookiesConfigured
        )
    }

    func isImmediatelySchedulable(_ job: DownloadJob) -> Bool {
        job.state == .queued
            && !deferrals.contains { $0.id == job.id }
            && !rateLimiter.blocked(host: RateHost(urlString: job.request.url), now: dependencies.clock.now)
    }

    // The raw halt plus derived reasons (an open circuit) the queue must surface as halted.
    func effectiveQueueHalt() -> QueueHaltReason? {
        if queueHalt == .depMissing {
            return .depMissing
        }
        if queueHalt == .networkDown {
            return .networkDown
        }
        guard !rateLimiter.circuitOpenHosts.isEmpty else {
            return nil
        }
        let hasLiveWork = jobs.contains { $0.state == .running || $0.state == .probing }
        if hasLiveWork || startableQueuedJobExists() {
            return nil
        }
        return .circuitOpen
    }

    private func startableQueuedJobExists() -> Bool {
        let now = dependencies.clock.now
        return jobs.contains { job in
            job.state == .queued
                && !deferrals.contains { $0.id == job.id }
                && !rateLimiter.blocked(host: RateHost(urlString: job.request.url), now: now)
        }
    }

    func emitSnapshot() {
        eventContinuation.yield(.snapshot(buildSnapshot()))
        persistProjections()
    }

    func emitProgress(_ delta: [UUID: Progress]) {
        eventContinuation.yield(.progress(delta, revision: revision))
    }

    // Every structural change reprojects; the debounce + unchanged-skip live in Persistence.
    private func persistProjections() {
        let persisted = jobs.map(Self.persistedJob(from:))
        let terminal = persisted.filter { isTerminal($0.state) }
        let active = persisted.filter { !isTerminal($0.state) }
        dependencies.persistence.saveQueue(active)
        dependencies.persistence.saveHistory(terminal)
    }

    private func isTerminal(_ state: PersistedState) -> Bool {
        switch state {
        case .completed, .cancelled, .failed: true
        case .queued, .paused: false
        }
    }

    static func persistedJob(from job: DownloadJob) -> PersistedJob {
        PersistedJob(
            id: job.id,
            request: job.request,
            title: job.title,
            extractor: job.extractor,
            durationSeconds: job.durationSeconds,
            state: PersistedState.persisted(from: job.state),
            attempt: job.attempt,
            playlistGroupID: job.playlistGroupID,
            playlistIndex: job.playlistIndex,
            addedAt: job.addedAt,
            finishedAt: job.finishedAt,
            sizeBytes: job.sizeBytes,
            actualQuality: job.actualQuality,
            progressFraction: persistedFraction(for: job),
            downloadedBytes: persistedProgress(for: job)?.downloadedBytes,
            totalBytes: persistedProgress(for: job)?.totalBytes ?? job.sizeBytes,
            outputFiles: job.outputFiles,
            playerClientUsed: job.playerClientUsed
        )
    }

    static func downloadJob(from persisted: PersistedJob) -> DownloadJob {
        let job = DownloadJob(
            request: persisted.request,
            id: persisted.id,
            addedAt: persisted.addedAt
        )
        job.title = persisted.title
        job.extractor = persisted.extractor
        job.durationSeconds = persisted.durationSeconds
        job.attempt = persisted.attempt
        job.state = persisted.state.restoredJobState
        job.finishedAt = persisted.finishedAt
        job.playlistGroupID = persisted.playlistGroupID
        job.playlistIndex = persisted.playlistIndex
        job.sizeBytes = persisted.sizeBytes
        job.actualQuality = persisted.actualQuality
        job.outputFiles = persisted.outputFiles
        job.playerClientUsed = persisted.playerClientUsed
        job.progress = restoredProgress(persisted)
        return job
    }

    // A quit clamps .running to .queued, so a live fraction would come back as a stale queued bar.
    private static func persistedProgress(for job: DownloadJob) -> Progress? {
        switch job.state {
        case .paused, .completed, .failed, .cancelled:
            job.progress
        default:
            nil
        }
    }

    private static func persistedFraction(for job: DownloadJob) -> Double? {
        persistedProgress(for: job)?.fraction
    }

    private static func restoredProgress(_ persisted: PersistedJob) -> Progress? {
        switch persisted.state {
        case .completed:
            return Progress(
                fraction: 1,
                downloadedBytes: persisted.sizeBytes ?? persisted.downloadedBytes ?? 0,
                totalBytes: persisted.sizeBytes ?? persisted.totalBytes
            )
        case .paused, .failed, .cancelled:
            guard let fraction = persisted.progressFraction else { return nil }
            return Progress(
                fraction: fraction,
                downloadedBytes: persisted.downloadedBytes ?? 0,
                totalBytes: persisted.totalBytes
            )
        case .queued:
            return nil
        }
    }

    func logEvent(_ event: LogEvent) {
        guard let log = dependencies.log else { return }
        Task { await log.log(event) }
    }

    func runningCount() -> Int {
        jobs.filter { $0.state == .running }.count
    }

    func queuedCount() -> Int {
        jobs.filter { $0.state == .queued }.count
    }

    // MARK: - Job-list helpers

    func queuedJob(_ id: UUID) -> DownloadJob? {
        guard let job = jobs.first(where: { $0.id == id }) else { return nil }
        return job.state == .queued ? job : nil
    }

    func runningJobs() -> [DownloadJob] {
        jobs.filter { $0.state == .running }
    }

    func oldestStartedRunningJob() -> DownloadJob? {
        runningJobs().min { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    func move(_ job: DownloadJob, toTail: Bool) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs.remove(at: index)
        if toTail {
            jobs.append(job)
        } else {
            jobs.insert(job, at: 0)
        }
    }
}
