import Foundation

public protocol DownloadEngineProtocol: Sendable {
    @discardableResult
    func submit(_ request: DownloadRequest) async -> DownloadJob
    func cancel(_ jobID: UUID) async
}

public actor DownloadEngine: DownloadEngineProtocol {
    private let ytDlpURL: URL
    private let runner: ProcessRunning
    private let probe: MetadataProbing

    private var queuedJobs: [DownloadJob] = []
    public private(set) var jobs: [DownloadJob] = []
    private var drainTask: Task<Void, Never>?
    private var runningLineTask: Task<Void, Never>?

    public init(
        ytDlpURL: URL,
        runner: ProcessRunning = ProcessRunner(),
        probe: MetadataProbing? = nil
    ) {
        self.ytDlpURL = ytDlpURL
        self.runner = runner
        self.probe = probe ?? MetadataProbe(ytDlpURL: ytDlpURL, runner: runner)
    }

    @discardableResult
    public func submit(_ request: DownloadRequest) async -> DownloadJob {
        let job = await MainActor.run { DownloadJob(request: request) }
        jobs.append(job)
        queuedJobs.append(job)
        ensureDraining()
        return job
    }

    public func cancel(_ jobID: UUID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let state = await MainActor.run { job.state }
        switch state {
        case .running:
            runningLineTask?.cancel()
        case .queued:
            await MainActor.run { job.state = .cancelled }
        default:
            break
        }
    }

    private func ensureDraining() {
        guard drainTask == nil else { return }
        drainTask = Task { await self.drain() }
    }

    private func drain() async {
        while let job = await nextQueued() {
            await run(job)
        }
        drainTask = nil
    }

    private func nextQueued() async -> DownloadJob? {
        while !queuedJobs.isEmpty {
            let job = queuedJobs.removeFirst()
            if await MainActor.run(body: { job.state }) == .cancelled {
                continue
            }
            return job
        }
        return nil
    }

    private func run(_ job: DownloadJob) async {
        await MainActor.run { job.state = .probing }
        let metadata = await probe.probe(job.request.url)

        switch metadata {
        case let .success(meta):
            await MainActor.run { job.title = meta.title }
        case let .failure(error):
            await MainActor.run {
                job.state = .failed(Self.errorClass(for: error))
                job.finishedAt = .now
            }
            return
        }

        await MainActor.run { job.state = .running }

        let lineTask = Task { await self.pump(job) }
        runningLineTask = lineTask
        await lineTask.value
        runningLineTask = nil
    }

    private func pump(_ job: DownloadJob) async {
        let execution = runner.run(ProcessLaunch(
            executableURL: ytDlpURL,
            arguments: YtDlpArguments.build(for: job.request)
        ))

        async let processResult = execution.result()

        var lastError: ErrorClass?
        for await line in execution.lines {
            switch line {
            case let .stdout(text):
                if case let .progress(progress) = ProgressParser.parseStdout(text) {
                    await MainActor.run { job.progress = progress }
                }
            case let .stderr(text):
                if let classified = ProgressParser.classifyStderr(text) {
                    lastError = classified
                }
            }
        }

        let result = await processResult
        await finish(job, result: result, lastError: lastError)
    }

    private func finish(
        _ job: DownloadJob,
        result: ProcessResult,
        lastError: ErrorClass?
    ) async {
        if result.wasCancelled {
            await MainActor.run {
                job.state = .cancelled
                job.finishedAt = .now
            }
            return
        }
        if result.exitCode == 0 {
            let files = await resolveOutputFiles(for: job)
            await MainActor.run {
                job.outputFiles = files
                job.state = .completed
                job.finishedAt = .now
            }
            return
        }
        let failure = lastError ?? .unknown(raw: "yt-dlp exited \(result.exitCode)")
        await MainActor.run {
            job.state = .failed(failure)
            job.finishedAt = .now
        }
    }

    private func resolveOutputFiles(for job: DownloadJob) async -> [URL] {
        guard let title = await MainActor.run(body: { job.title }) else { return [] }
        let stem = Self.titleStem(title)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: job.request.destFolder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.lastPathComponent.hasPrefix(stem) }
            .sorted { modificationDate($0) > modificationDate($1) }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    // yt-dlp's %(title)s sanitiser strips path separators and control characters.
    private static func titleStem(_ title: String) -> String {
        String(title.unicodeScalars.filter { scalar in
            scalar != "/" && !CharacterSet.controlCharacters.contains(scalar)
        })
    }

    private static func errorClass(for error: MetadataError) -> ErrorClass {
        switch error {
        case .network:
            .networkDown
        case .ytDlpMissing:
            .depMissing
        case let .unknown(raw):
            .unknown(raw: raw)
        case .badURL, .unsupported, .unavailable, .malformedOutput:
            .unknown(raw: "\(error)")
        }
    }
}
