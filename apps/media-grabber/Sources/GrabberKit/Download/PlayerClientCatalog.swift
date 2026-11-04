import Foundation

public protocol PlayerClientOrdering: Sendable {
    func order() async -> [String]
}

public struct BundledPlayerClientOrder: PlayerClientOrdering {
    public init() {}

    public func order() async -> [String] {
        PlayerClientRotation.bundled
    }
}

public struct LivePlayerClientOrder: PlayerClientOrdering {
    private let store: PlayerClientCatalogStore

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        store = PlayerClientCatalogStore(directory: directory, now: now)
    }

    public func order() async -> [String] {
        await store.order {
            let (data, _) = try await URLSession.shared.data(for: PlayerClientCatalog.request())
            return data
        }
    }
}

public enum PlayerClientCatalog {
    public static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/Mshardul/Tools/main/apps/media-grabber/config/player-clients.json"
    )!

    public static func request() -> URLRequest {
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 5
        return request
    }

    public static func clients(from data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clients = object["playerClients"] as? [String],
              !clients.isEmpty,
              clients.allSatisfy(isClientName)
        else {
            return nil
        }
        return clients
    }

    private static func isClientName(_ name: String) -> Bool {
        name.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil
    }
}

public struct PlayerClientCatalogStore: Sendable {
    private let directory: URL
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval
    private let failureBackoff: TimeInterval

    public init(
        directory: URL,
        now: @escaping @Sendable () -> Date,
        maxAge: TimeInterval = 86400,
        failureBackoff: TimeInterval = 3600
    ) {
        self.directory = directory
        self.now = now
        self.maxAge = maxAge
        self.failureBackoff = failureBackoff
    }

    public func order(fetch: @Sendable () async throws -> Data) async -> [String] {
        let saved = read()
        if let saved, !saved.clients.isEmpty, now().timeIntervalSince(saved.fetchedAt) < maxAge {
            return saved.clients
        }
        if let saved, let failedAt = saved.failedAt, now().timeIntervalSince(failedAt) < failureBackoff {
            return saved.clients.isEmpty ? PlayerClientRotation.bundled : saved.clients
        }
        do {
            let data = try await fetch()
            if let clients = PlayerClientCatalog.clients(from: data) {
                write(clients: clients, fetchedAt: now(), failedAt: nil)
                return clients
            }
        } catch {
            // A failed fetch keeps the last accepted list.
        }
        write(
            clients: saved?.clients ?? [],
            fetchedAt: saved?.fetchedAt ?? now(),
            failedAt: now()
        )
        if let clients = saved?.clients, !clients.isEmpty {
            return clients
        }
        return PlayerClientRotation.bundled
    }

    private var fileURL: URL {
        directory.appendingPathComponent("catalog.json")
    }

    private struct Record {
        var clients: [String]
        var fetchedAt: Date
        var failedAt: Date?
    }

    private func read() -> Record? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clients = object["playerClients"] as? [String],
              let stamp = object["fetchedAt"] as? String,
              let fetchedAt = ISO8601DateFormatter().date(from: stamp)
        else {
            return nil
        }
        let failedAt = (object["failedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return Record(clients: clients, fetchedAt: fetchedAt, failedAt: failedAt)
    }

    private func write(clients: [String], fetchedAt: Date, failedAt: Date?) {
        let formatter = ISO8601DateFormatter()
        var object: [String: Any] = [
            "playerClients": clients,
            "fetchedAt": formatter.string(from: fetchedAt)
        ]
        if let failedAt {
            object["failedAt"] = formatter.string(from: failedAt)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
