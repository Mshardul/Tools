import Foundation

// One redacted stdout/stderr transcript per job at <dir>/<id>.log, owned by a single launcher task.
public final class JobLog: @unchecked Sendable {
    private let id: UUID
    private let request: DownloadRequest
    private let ytDlpVersion: String
    private let playerClient: String?
    private let fileURL: URL
    private var handle: FileHandle?

    public init(
        id: UUID,
        request: DownloadRequest,
        ytDlpVersion: String,
        playerClient: String? = nil,
        dir: URL = JobLog.defaultDir
    ) {
        self.id = id
        self.request = request
        self.ytDlpVersion = ytDlpVersion
        self.playerClient = playerClient
        fileURL = dir.appendingPathComponent("\(id.uuidString).log")
    }

    public func writeHeader() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let header = """
        url: \(LogRedaction.redact(request.url))
        request: \(LogRedaction.redact(Self.describe(request)))
        started: \(ISO8601DateFormatter().string(from: Date()))
        yt-dlp: \(ytDlpVersion)
        player_client: \(playerClient ?? "-")
        ----
        """
        try (header + "\n").data(using: .utf8)?.write(to: fileURL)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        self.handle = handle
    }

    public func append(_ line: ProcessLine) {
        let text: String = switch line {
        case let .stdout(value): LogRedaction.redact(value)
        case let .stderr(value): "[stderr] " + LogRedaction.redact(value)
        }
        guard let data = (text + "\n").data(using: .utf8) else { return }
        try? handle?.write(contentsOf: data)
    }

    public func close() {
        try? handle?.close()
        handle = nil
    }

    // MARK: - Statics

    public static var defaultDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MediaGrabber/jobs", isDirectory: true)
    }

    public static func delete(id: UUID, dir: URL = defaultDir) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).log"))
    }

    // Keeps the newest `limit` by the job's finishedAt, not file mtime — a restored job's file is old, the job fresh.
    public static func evict(
        keepingNewestByFinishedAt jobs: [(id: UUID, finishedAt: Date?)],
        limit: Int = 200,
        dir: URL = defaultDir
    ) {
        let terminal = jobs
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        guard terminal.count > limit else { return }
        for job in terminal.dropFirst(limit) {
            delete(id: job.id, dir: dir)
        }
    }

    private static func describe(_ request: DownloadRequest) -> String {
        let kind = switch request.kind {
        case let .video(maxHeight): "video<=\(maxHeight)"
        case let .audio(format): "audio:\(format.rawValue)"
        }
        let container = request.container ?? "-"
        return "\(kind) container=\(container) template=\(request.filenameTemplate) "
            + "dest=\(request.destFolder.path)"
    }
}
