import Foundation

public struct ConfirmationRequest: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    public let confirmTitle: String
    // nil → a single-button notice, no choice.
    public let cancelTitle: String?
    public let isDestructive: Bool
    // non-nil → a "Don't ask again" checkbox, persisted to AppStorage under this key.
    public let suppressionKey: String?

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        confirmTitle: String,
        cancelTitle: String?,
        isDestructive: Bool = false,
        suppressionKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.suppressionKey = suppressionKey
    }

    public var showsCancel: Bool {
        cancelTitle != nil
    }
}

public protocol Confirming: Sendable {
    func confirm(_ request: ConfirmationRequest) async -> Bool
}
