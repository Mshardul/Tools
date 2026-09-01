import Foundation

public extension ErrorClass {
    // A stable token for logs and the later diagnostics report — not user-facing.
    var key: String {
        switch self {
        case .rateLimited: "rate_limited"
        case .botCheck: "bot_check"
        case .sabrGated: "sabr_gated"
        case .formatsMissing: "formats_missing"
        case .cookieReadFailed: "cookie_read_failed"
        case .geoBlocked: "geo_blocked"
        case .private: "private"
        case .unavailable: "unavailable"
        case .ageRestricted: "age_restricted"
        case .networkDown: "network_down"
        case .diskFull: "disk_full"
        case .permissionDenied: "permission_denied"
        case .incomplete: "incomplete"
        case .depMissing: "dep_missing"
        case .potProviderDown: "pot_provider_down"
        case .unknown: "unknown"
        }
    }

    var retryAfterSeconds: Int? {
        if case let .rateLimited(seconds) = self {
            return seconds
        }
        return nil
    }

    var presentation: FailurePresentation {
        FailurePresentation.for(self)
    }

    var isAutoRetryable: Bool {
        switch self {
        case .rateLimited, .networkDown, .incomplete, .unknown: true
        default: false
        }
    }
}
