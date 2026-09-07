import Foundation
import GrabberKit

public struct FakePinger: ShieldPinging {
    public var result: Bool

    public init(_ result: Bool = true) {
        self.result = result
    }

    public func ping(_: URL, timeout _: TimeInterval) async -> Bool {
        result
    }
}

public actor FakePotProvider: PotProviding {
    public var status: ShieldStatus
    public var baseURL: URL?
    public var pluginDirs: [URL]
    public private(set) var ensureCount = 0
    public private(set) var restartCount = 0
    public private(set) var stopCount = 0

    public init(
        status: ShieldStatus = .missing,
        baseURL: URL? = nil,
        pluginDirs: [URL] = []
    ) {
        self.status = status
        self.baseURL = baseURL
        self.pluginDirs = pluginDirs
    }

    public func ensure() async {
        ensureCount += 1
    }

    public func restart() async {
        restartCount += 1
    }

    public func stop() async {
        stopCount += 1
    }
}
