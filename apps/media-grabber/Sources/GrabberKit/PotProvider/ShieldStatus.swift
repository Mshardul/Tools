import Foundation

public enum ShieldStatus: Sendable, Equatable {
    case running(port: Int)
    case down
    case missing
}
