import Foundation

public enum SignInScope: String, Codable, Sendable {
    case allSites
    case listedSites
}

public enum SignInScopePolicy {
    public static func sendsCookies(scope: SignInScope, sites: [String], host: String) -> Bool {
        switch scope {
        case .allSites:
            true
        case .listedSites:
            sites.contains(host)
        }
    }
}
