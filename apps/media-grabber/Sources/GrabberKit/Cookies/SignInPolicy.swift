import Foundation

public enum SignInAdvice: Sendable, Equatable {
    case none
    case suggest
    case checkBrowser
}

public enum SignInPolicy {
    public static func fixableBySignIn(_ errorClass: ErrorClass, host: RateHost) -> Bool {
        switch errorClass {
        case .ageRestricted, .private: true
        case .botCheck: host.canonical == "youtube"
        default: false
        }
    }

    public static func advice(for errorClass: ErrorClass, host: RateHost, cookiesConfigured: Bool) -> SignInAdvice {
        guard fixableBySignIn(errorClass, host: host) else { return .none }
        return cookiesConfigured ? .checkBrowser : .suggest
    }

    public static func probeAdvice(for error: MetadataError, host: RateHost, cookiesConfigured: Bool) -> SignInAdvice {
        let errorClass: ErrorClass
        switch error {
        case .ageRestricted: errorClass = .ageRestricted
        case .private: errorClass = .private
        case .botCheck: errorClass = .botCheck
        default: return .none
        }
        return advice(for: errorClass, host: host, cookiesConfigured: cookiesConfigured)
    }
}
