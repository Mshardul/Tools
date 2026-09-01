import Foundation

public protocol DownloadEngineProtocol: Sendable {
    var events: AsyncStream<QueueEvent> { get }
    func currentSnapshot() async -> QueueSnapshot
    func hasActiveJobs() async -> Bool

    func submit(
        _ request: DownloadRequest,
        force: Bool,
        prefetchedMetadata: MediaMetadata?
    ) async -> SubmitResult
    func restore(active: [PersistedJob], history: [PersistedJob]) async
    func revalidate() async

    func pause(_ id: UUID) async
    func resume(_ id: UUID) async
    func retry(_ id: UUID) async
    func cancel(_ id: UUID) async
    func remove(_ id: UUID) async
    func forceStart(_ id: UUID) async

    func shutdown() async
}

public struct EngineDebugFlags: Sendable {
    public var concurrencyCapOverride: Int?

    public init(concurrencyCapOverride: Int? = nil) {
        self.concurrencyCapOverride = concurrencyCapOverride
    }
}

public struct EngineDependencies: Sendable {
    public var runner: ProcessRunning
    public var probe: MetadataProbing
    public var envProbe: EnvironmentProbing
    public var clock: any Clock
    public var ytDlpURL: URL
    public var ytDlpVersion: String
    public var jobLogDir: URL
    public var debugFlags: EngineDebugFlags
    public var tuning: EngineTuning
    public var ffprobeURL: URL?
    public var log: LogWriter?
    public var persistence: any QueuePersisting
    // Called on remove(_:) to delete the job's raw log; defaults to JobLog.delete.
    public var deleteJobLog: (@Sendable (UUID) -> Void)?

    public init(
        runner: ProcessRunning,
        probe: MetadataProbing,
        envProbe: EnvironmentProbing,
        clock: any Clock = SystemClock(),
        ytDlpURL: URL,
        ytDlpVersion: String = "unknown",
        jobLogDir: URL = JobLog.defaultDir,
        debugFlags: EngineDebugFlags = .init(),
        tuning: EngineTuning = .default,
        ffprobeURL: URL? = nil,
        log: LogWriter? = nil,
        persistence: any QueuePersisting = NoopPersisting(),
        deleteJobLog: (@Sendable (UUID) -> Void)? = nil
    ) {
        self.runner = runner
        self.probe = probe
        self.envProbe = envProbe
        self.clock = clock
        self.ytDlpURL = ytDlpURL
        self.ytDlpVersion = ytDlpVersion
        self.jobLogDir = jobLogDir
        self.debugFlags = debugFlags
        self.tuning = tuning
        self.ffprobeURL = ffprobeURL
        self.log = log
        self.persistence = persistence
        if let deleteJobLog {
            self.deleteJobLog = deleteJobLog
        } else {
            self.deleteJobLog = { id in JobLog.delete(id: id, dir: jobLogDir) }
        }
    }

    public static func live(
        ytDlpURL: URL,
        ffprobeURL: URL? = nil,
        debugFlags: EngineDebugFlags = .init(),
        log: LogWriter? = nil,
        persistence: (any QueuePersisting)? = nil
    ) -> EngineDependencies {
        let runner = ProcessRunner()
        return EngineDependencies(
            runner: runner,
            probe: MetadataProbe(ytDlpURL: ytDlpURL, runner: runner),
            envProbe: EnvironmentProbe(),
            clock: SystemClock(),
            ytDlpURL: ytDlpURL,
            debugFlags: debugFlags,
            tuning: .resolved(),
            ffprobeURL: ffprobeURL ?? Self.locateFfprobe(),
            log: log,
            persistence: persistence ?? NoopPersisting()
        )
    }

    private static func locateFfprobe() -> URL? {
        ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }
}

public struct NoopPersisting: QueuePersisting {
    public init() {}
    public func saveQueue(_: [PersistedJob]) {}
    public func saveHistory(_: [PersistedJob]) {}
    public func saveColumns(_: ColumnConfig) {}
    public func flushNow() async {}
    public func loadQueue() -> [PersistedJob] {
        []
    }

    public func loadHistory() -> [PersistedJob] {
        []
    }

    public func loadColumns() -> ColumnConfig? {
        nil
    }
}
