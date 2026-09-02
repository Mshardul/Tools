import Foundation

public enum SafariCookieAccess: Sendable, Equatable {
    case granted
    case denied
    case noContainer
}

public enum CookieVerdict: Sendable, Equatable {
    case unconfigured
    case ready(browserKey: String)
    case needsFullDiskAccess
    case noProfiles
}

public struct CookieResolution: Sendable, Equatable {
    public let argument: String?
    public let verdict: CookieVerdict

    public init(argument: String?, verdict: CookieVerdict) {
        self.argument = argument
        self.verdict = verdict
    }
}
