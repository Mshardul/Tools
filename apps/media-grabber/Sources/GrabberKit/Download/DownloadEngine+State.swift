import Foundation

extension DownloadEngine {
    // MARK: - Snapshot / emit

    func buildSnapshot() -> QueueSnapshot {
        QueueSnapshot(
            jobs: jobs.map { $0.snapshot(availableActions: Self.availableActions(for: $0.state)) },
            revision: revision,
            queueHalt: queueHalt,
            generatedAt: .now
        )
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
            forceCookies: job.forceCookies,
            playlistGroupID: nil,
            addedAt: job.addedAt,
            finishedAt: job.finishedAt
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
        job.forceCookies = persisted.forceCookies
        job.state = persisted.state.restoredJobState
        job.finishedAt = persisted.finishedAt
        return job
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
