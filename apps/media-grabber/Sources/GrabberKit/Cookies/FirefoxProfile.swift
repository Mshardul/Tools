import Foundation

public struct FirefoxProfile: Sendable, Equatable, Identifiable {
    public var id: String {
        name
    }

    public let name: String
    public let path: String
    public let isDefault: Bool

    public init(name: String, path: String, isDefault: Bool) {
        self.name = name
        self.path = path
        self.isDefault = isDefault
    }
}
