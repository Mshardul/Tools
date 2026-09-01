public enum ErrorClass: Sendable, Equatable {
    case rateLimited(retryAfterSeconds: Int? = nil)
    case botCheck
    case sabrGated
    case formatsMissing
    case cookieReadFailed
    case geoBlocked
    case `private`
    case unavailable
    case ageRestricted
    case networkDown
    case diskFull
    case permissionDenied
    case incomplete
    case depMissing
    case potProviderDown
    case unknown(raw: String)
}
