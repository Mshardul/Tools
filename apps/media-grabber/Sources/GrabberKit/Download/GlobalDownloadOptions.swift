import Foundation

public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var speedLimitKBps: Int

    public init(proxyURL: String?, forceIPv4: Bool, speedLimitKBps: Int) {
        self.proxyURL = proxyURL
        self.forceIPv4 = forceIPv4
        self.speedLimitKBps = speedLimitKBps
    }

    public static let none = GlobalDownloadOptions(
        proxyURL: nil,
        forceIPv4: false,
        speedLimitKBps: 0
    )
}
