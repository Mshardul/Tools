import Foundation

public actor DownloadEngine: DownloadEngineProtocol {
    let dependencies: EngineDependencies
    let preferences: Preferences

    var jobs: [DownloadJob] = []
    var revision: UInt64 = 0
    var queueHalt: QueueHaltReason?
    var deferrals: [(id: UUID, notBefore: Date)] = []
    var deferralTask: Task<Void, Never>?
    var probeInFlight = false
    var capOverrideForTests: Int?

    let eventStream: AsyncStream<QueueEvent>
    let eventContinuation: AsyncStream<QueueEvent>.Continuation

    public nonisolated let events: AsyncStream<QueueEvent>

    public init(dependencies: EngineDependencies, preferences: Preferences) {
        self.dependencies = dependencies
        self.preferences = preferences
        let (stream, continuation) = AsyncStream<QueueEvent>.makeStream()
        eventStream = stream
        eventContinuation = continuation
        events = stream
    }

    // MARK: - Cap

    var cap: Int {
        if let capOverrideForTests {
            return capOverrideForTests
        }
        return dependencies.debugFlags.concurrencyCapOverride ?? preferences.maxConcurrentDownloads
    }

    // Test seam: drive cap deterministically without a Preferences round-trip.
    func setCap(_ value: Int?) {
        capOverrideForTests = value
        evaluateSchedule()
    }

    // MARK: - Queries

    public func currentSnapshot() -> QueueSnapshot {
        buildSnapshot()
    }

    public func hasActiveJobs() -> Bool {
        jobs.contains { isActive($0.state) }
    }

    private func isActive(_ state: JobState) -> Bool {
        switch state {
        case .probing, .running: true
        default: false
        }
    }

    // MARK: - Intents

    public func submit(
        _ request: DownloadRequest,
        force: Bool,
        prefetchedMetadata: MediaMetadata?
    ) async -> SubmitResult {
        if !force, let existing = jobs.first(where: { $0.request == request }) {
            return .duplicateExists(
                existing: existing.id,
                wasCompleted: existing.state == .completed
            )
        }
        let job = DownloadJob(request: request)
        if let meta = prefetchedMetadata {
            job.title = meta.title
            job.extractor = meta.extractor
            job.durationSeconds = meta.durationSeconds
        }
        jobs.append(job)
        let position = queuedCount()
        bump()
        emitSnapshot()
        logEvent(.jobEnqueued(id: job.id, url: request.url, queuePosition: position))
        evaluateSchedule()
        return .queued(job.id)
    }

    private(set) var producedJobsOnRestore = false

    public func restore(active: [PersistedJob], history: [PersistedJob]) async {
        jobs = (active + history).map(Self.downloadJob(from:))
        producedJobsOnRestore = !jobs.isEmpty
        if producedJobsOnRestore {
            bump()
            emitSnapshot()
        }
        evaluateSchedule()
    }

    public func revalidate() async {
        let report = await dependencies.envProbe.probe()
        guard report.isReadyForDownloads else { return }
        queueHalt = nil
        bump()
        emitSnapshot()
        evaluateSchedule()
    }

    public func pause(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .running else { return }
        job.state = .paused
        bump()
        emitSnapshot()
        logEvent(.jobPaused(id: id))
        childTasks[id]?.cancel()
        evaluateSchedule()
    }

    public func resume(_ id: UUID) async {
        guard let index = pausedJobIndex(id) else { return }
        let job = jobs.remove(at: index)
        job.state = .queued
        job.progress = nil
        job.sizeBytes = nil
        jobs.append(job)
        bump()
        emitSnapshot()
        logEvent(.jobResumed(id: id))
        evaluateSchedule()
    }

    public func cancel(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        switch job.state {
        case .running, .probing:
            cancelChild(id)
        case .queued, .paused:
            markCancelled(id)
        default:
            break
        }
    }

    public func remove(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]
        let wasRunning = job.state == .running || job.state == .probing
        if wasRunning {
            childTasks[id]?.cancel()
        }
        deletePartFiles(for: job)
        dependencies.deleteJobLog?(id)
        jobs.remove(at: index)
        childTasks[id] = nil
        bump()
        emitSnapshot()
        logEvent(.jobRemoved(id: id, wasRunning: wasRunning))
        evaluateSchedule()
    }

    public func forceStart(_ id: UUID) async {
        guard let forced = queuedJob(id) else { return }

        let victim = runningJobs().count >= cap ? oldestStartedRunningJob() : nil
        if let victim {
            move(victim, toTail: true)
            victim.state = .queued
            victim.progress = nil
        }
        move(forced, toTail: false)
        forced.state = .running
        forced.startedAt = .now

        bump()
        emitSnapshot()
        logEvent(.jobForceStarted(id: id, evicted: victim?.id))

        if let victim {
            childTasks[victim.id]?.cancel()
        }
        launchDownload(id: id)
        evaluateSchedule()
    }

    public func shutdown() async {
        for job in jobs where job.state == .running || job.state == .probing {
            childTasks[job.id]?.cancel()
        }
        probeTask?.cancel()
        deferralTask?.cancel()
        deferralTask = nil
        for (_, task) in childTasks {
            await task.value
        }
        if let probeTask {
            await probeTask.value
        }
    }

    // MARK: - Detached work handles

    var childTasks: [UUID: Task<Void, Never>] = [:]
    var probeTask: Task<Void, Never>?

    private func cancelChild(_ id: UUID) {
        childTasks[id]?.cancel()
    }

    private func pausedJobIndex(_ id: UUID) -> Int? {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return nil }
        return jobs[index].state == .paused ? index : nil
    }

    func bump() {
        revision += 1
    }
}

// MARK: - Scheduling

extension DownloadEngine {
    func evaluateSchedule() {
        guard queueHalt == nil else { return }
        let input = SchedulerInput(
            queued: snapshotsForState { $0 == .queued },
            running: snapshotsForState { $0 == .running },
            cap: cap,
            deferredIDs: Set(deferrals.map(\.id)),
            probeIdle: !probeInFlight
        )
        for id in Scheduler.nextDownloads(input) {
            markRunning(id)
            launchDownload(id: id)
        }
        if !probeInFlight, let probeID = Scheduler.nextProbe(input) {
            probeInFlight = true
            markProbing(probeID)
            launchProbe(id: probeID)
        }
    }

    private func snapshotsForState(_ match: (JobState) -> Bool) -> [JobSnapshot] {
        jobs.filter { match($0.state) }.map { $0.snapshot(availableActions: []) }
    }

    private func launchDownload(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let request = job.request
        let runner = dependencies.runner
        let ytDlpURL = dependencies.ytDlpURL
        let jobLog = JobLog(
            id: id,
            request: request,
            ytDlpVersion: dependencies.ytDlpVersion,
            dir: dependencies.jobLogDir
        )
        let task = Task { [weak self] in
            let execution = runner.run(ProcessLaunch(
                executableURL: ytDlpURL,
                arguments: YtDlpArguments.build(for: request)
            ))
            try? jobLog.writeHeader()
            async let processResult = execution.result()
            var lastError: ErrorClass?
            var launchFailed = false
            for await line in execution.lines {
                jobLog.append(line)
                let text: String
                switch line {
                case let .stdout(stdout):
                    text = stdout
                    if case let .progress(progress) = ProgressParser.parseStdout(stdout) {
                        await self?.recordProgress(id, progress)
                    }
                case let .stderr(stderr):
                    text = stderr
                    if stderr.hasPrefix("launch failed:") {
                        launchFailed = true
                    }
                    if let classified = ProgressParser.classifyStderr(stderr) {
                        lastError = classified
                    }
                }
                if let path = ProgressParser.captureOutputPath(from: text) {
                    await self?.recordOutputPath(id, path)
                }
            }
            let result = await processResult
            jobLog.close()
            await self?.recordExit(
                id,
                result,
                lastError: lastError,
                launchFailed: launchFailed && result.exitCode == 127
            )
        }
        childTasks[id] = task
    }

    private func launchProbe(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let url = job.request.url
        let probe = dependencies.probe
        let task = Task { [weak self] in
            let result = await probe.probe(url)
            await self?.recordProbeResult(id, result)
        }
        probeTask = task
    }
}
