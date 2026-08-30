import Foundation

public struct QueueFile: Codable, Sendable {
    public var schemaVersion: Int
    public var jobs: [PersistedJob]
}

public struct HistoryFile: Codable, Sendable {
    public var schemaVersion: Int
    public var jobs: [PersistedJob]
}

public struct ColumnsFile: Codable, Sendable {
    public var schemaVersion: Int
    public var config: ColumnConfig
}

public struct PersistenceDebug: Sendable {
    public var resetState: Bool

    public init(resetState: Bool = false) {
        self.resetState = resetState
    }
}

public protocol QueuePersisting: Sendable {
    func saveQueue(_ jobs: [PersistedJob])
    func saveHistory(_ jobs: [PersistedJob])
    func saveColumns(_ config: ColumnConfig)
    func flushNow() async
    func loadQueue() -> [PersistedJob]
    func loadHistory() -> [PersistedJob]
    func loadColumns() -> ColumnConfig?
}

public final class Persistence: QueuePersisting {
    static let schemaVersion = 1
    static let historyCap = 200
    static let debounce: TimeInterval = 0.5

    private struct Pending {
        var queue: [PersistedJob]?
        var history: [PersistedJob]?
        var columns: ColumnConfig?
    }

    private let dir: URL
    private let log: LogWriter
    private let debug: PersistenceDebug
    private let clock: any Clock
    private let pending = Locked(Pending())
    private let writer: Writer

    public init(
        dir: URL = Persistence.defaultDir,
        clock: any Clock = SystemClock(),
        log: LogWriter,
        debug: PersistenceDebug = .init()
    ) {
        self.dir = dir
        self.log = log
        self.debug = debug
        self.clock = clock
        writer = Writer(dir: dir, log: log)
    }

    public static var defaultDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MediaGrabber", isDirectory: true)
    }

    var didFirstWriteFail: Bool {
        get async { await writer.didFirstWriteFail }
    }

    // MARK: - Saves (synchronous stash + debounced write)

    public func saveQueue(_ jobs: [PersistedJob]) {
        pending.mutate { $0.queue = jobs }
        armDebounce()
    }

    public func saveHistory(_ jobs: [PersistedJob]) {
        pending.mutate { $0.history = Self.cappedHistory(jobs) }
        armDebounce()
    }

    public func saveColumns(_ config: ColumnConfig) {
        pending.mutate { $0.columns = config }
        armDebounce()
    }

    public func flushNow() async {
        debounceTask.read { $0 }?.cancel()
        await writePending()
    }

    private let debounceTask = Locked<Task<Void, Never>?>(nil)

    private func armDebounce() {
        debounceTask.read { $0 }?.cancel()
        let deadline = clock.now.addingTimeInterval(Self.debounce)
        let clock = clock
        let task = Task { [weak self] in
            await clock.sleep(until: deadline)
            guard !Task.isCancelled else { return }
            await self?.writePending()
        }
        debounceTask.mutate { $0 = task }
    }

    private func writePending() async {
        let snapshot: Pending = pending.mutate { current in
            let taken = current
            current = Pending()
            return taken
        }
        if let jobs = snapshot.queue {
            await writer.write(
                QueueFile(schemaVersion: Self.schemaVersion, jobs: jobs),
                to: "queue.json"
            )
        }
        if let jobs = snapshot.history {
            await writer.write(
                HistoryFile(schemaVersion: Self.schemaVersion, jobs: jobs), to: "history.json"
            )
        }
        if let config = snapshot.columns {
            await writer.write(
                ColumnsFile(schemaVersion: Self.schemaVersion, config: config), to: "columns.json"
            )
        }
    }

    // MARK: - Loads (direct, stateless)

    public func loadQueue() -> [PersistedJob] {
        guard !debug.resetState else { return [] }
        return loadJobs(name: "queue.json", QueueFile.self)
    }

    public func loadHistory() -> [PersistedJob] {
        guard !debug.resetState else { return [] }
        return loadJobs(name: "history.json", HistoryFile.self)
    }

    public func loadColumns() -> ColumnConfig? {
        guard !debug.resetState else { return nil }
        let url = dir.appendingPathComponent("columns.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let file = try? JSONDecoder().decode(ColumnsFile.self, from: data) else {
            emit(.persistenceCorrupt(file: "columns.json"))
            return nil
        }
        if file.schemaVersion > Self.schemaVersion {
            emit(.persistenceSchemaAhead(file: "columns.json"))
            return nil
        }
        emit(.persistenceLoaded(file: "columns.json", count: file.config.visibleColumns.count))
        return file.config
    }

    private func loadJobs<F: SchemaVersioned>(name: String, _: F.Type) -> [PersistedJob] {
        let url = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let file = try? JSONDecoder().decode(F.self, from: data) else {
            emit(.persistenceCorrupt(file: name))
            return []
        }
        if file.schemaVersion > Self.schemaVersion {
            emit(.persistenceSchemaAhead(file: name))
            return []
        }
        emit(.persistenceLoaded(file: name, count: file.jobs.count))
        return file.jobs
    }

    private func emit(_ event: LogEvent) {
        Task { await log.log(event) }
    }

    static func cappedHistory(_ jobs: [PersistedJob]) -> [PersistedJob] {
        Array(
            jobs
                .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
                .prefix(historyCap)
        )
    }
}

protocol SchemaVersioned: Decodable {
    var schemaVersion: Int { get }
    var jobs: [PersistedJob] { get }
}

extension QueueFile: SchemaVersioned {}
extension HistoryFile: SchemaVersioned {}

// MARK: - The actor that owns file IO + the write-failure flag

extension Persistence {
    actor Writer {
        private let dir: URL
        private let log: LogWriter
        private var lastWritten: [String: Data] = [:]
        private(set) var didFirstWriteFail = false

        init(dir: URL, log: LogWriter) {
            self.dir = dir
            self.log = log
        }

        func write(_ value: some Encodable, to name: String) async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(value) else { return }
            guard data != lastWritten[name] else { return }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: dir.appendingPathComponent(name), options: .atomic)
                lastWritten[name] = data
                if didFirstWriteFail {
                    didFirstWriteFail = false
                    await log.log(.persistenceRecovered(file: name))
                }
            } catch {
                didFirstWriteFail = true
                await log.log(.persistenceWriteFailed(file: name, error: "\(error)"))
            }
        }
    }
}
