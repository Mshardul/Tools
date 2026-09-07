import Foundation

public protocol PotProviding: Sendable {
    var status: ShieldStatus { get async }
    func ensure() async
    func restart() async
    func stop() async
    var baseURL: URL? { get async }
    var pluginDirs: [URL] { get async }
}

public struct MissingPotProvider: PotProviding {
    public init() {}

    public var status: ShieldStatus {
        get async { .missing }
    }

    public func ensure() async {}

    public func restart() async {}

    public func stop() async {}

    public var baseURL: URL? {
        get async { nil }
    }

    public var pluginDirs: [URL] {
        get async { [] }
    }
}
