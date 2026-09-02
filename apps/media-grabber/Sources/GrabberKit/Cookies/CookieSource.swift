import Foundation

public enum CookieSource: Sendable, Hashable, Codable {
    case none
    case safari
    case chrome
    case brave
    case edge
    case firefox(profile: String?)

    public var browserKey: String {
        switch self {
        case .none: "none"
        case .safari: "safari"
        case .chrome: "chrome"
        case .brave: "brave"
        case .edge: "edge"
        case .firefox: "firefox"
        }
    }

    public var ytDlpSpec: String? {
        switch self {
        case .none: nil
        case .safari: "safari"
        case .chrome: "chrome"
        case .brave: "brave"
        case .edge: "edge"
        case let .firefox(profile):
            profile.map { "firefox:\($0)" } ?? "firefox"
        }
    }

    public var isNone: Bool {
        self == .none
    }
}
