import Foundation
import os

public actor LogWriter {
    public static let subsystem = "app.mediagrabber.mac"

    private let directory: URL
    private let minLevel: LogLevel
    private let clock: @Sendable () -> Date
    private let fileManager = FileManager.default

    private let maxFileBytes = 5 * 1024 * 1024
    private let maxFiles = 5

    private lazy var loggers: [LogCategory: Logger] = [
        .engine: Logger(subsystem: Self.subsystem, category: "engine"),
        .scheduler: Logger(subsystem: Self.subsystem, category: "scheduler"),
        .deps: Logger(subsystem: Self.subsystem, category: "deps"),
        .ui: Logger(subsystem: Self.subsystem, category: "ui"),
        .persistence: Logger(subsystem: Self.subsystem, category: "persistence")
    ]

    public init(
        directory: URL = LogWriter.defaultDirectory,
        minLevel: LogLevel = .info,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.minLevel = minLevel
        self.clock = clock
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/MediaGrabber", isDirectory: true)
    }

    public func log(_ event: LogEvent, level: LogLevel = .info) async {
        guard rank(level) >= rank(minLevel) else { return }
        let line = buildLine(event, level: level)
        mirror(event, level: level, line: line)
        write(line)
    }

    private func buildLine(_ event: LogEvent, level: LogLevel) -> String {
        var object: [String: Any] = [
            "ts": Self.timestamp(clock()),
            "level": level.rawValue,
            "category": event.category.rawValue,
            "event": event.key,
            "fields": LogRedaction.redact(event.fields)
        ]
        if let jobID = event.jobID {
            object["jobID"] = jobID.uuidString
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            ),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"event\":\"\(event.key)\"}"
        }
        return json
    }

    private func mirror(_ event: LogEvent, level: LogLevel, line: String) {
        let logger = loggers[event.category]
        switch level {
        case .debug: logger?.debug("\(line, privacy: .public)")
        case .info: logger?.info("\(line, privacy: .public)")
        case .warn: logger?.warning("\(line, privacy: .public)")
        case .error: logger?.error("\(line, privacy: .public)")
        }
    }

    private func write(_ line: String) {
        ensureDirectory()
        let fileURL = directory.appendingPathComponent("app.log")
        rotateIfNeeded(fileURL, appending: line.utf8.count + 1)
        appendLine(line, to: fileURL)
    }

    private func ensureDirectory() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func appendLine(_ line: String, to fileURL: URL) {
        let payload = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: fileURL)
        }
    }

    private func rotateIfNeeded(_ fileURL: URL, appending newBytes: Int) {
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size + newBytes > maxFileBytes else { return }

        let oldest = directory.appendingPathComponent("app.log.\(maxFiles - 1)")
        try? fileManager.removeItem(at: oldest)
        for index in stride(from: maxFiles - 2, through: 0, by: -1) {
            let source = index == 0
                ? fileURL
                : directory.appendingPathComponent("app.log.\(index)")
            let destination = directory.appendingPathComponent("app.log.\(index + 1)")
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    private func rank(_ level: LogLevel) -> Int {
        switch level {
        case .debug: 0
        case .info: 1
        case .warn: 2
        case .error: 3
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
