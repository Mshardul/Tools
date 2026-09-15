import Foundation
import GrabberKit

@MainActor
final class AppModelConfirmer: Confirming, @unchecked Sendable {
    weak var model: AppModel?

    func confirm(_ request: ConfirmationRequest) async -> Bool {
        guard let model else { return false }
        return await model.confirm(request)
    }
}
