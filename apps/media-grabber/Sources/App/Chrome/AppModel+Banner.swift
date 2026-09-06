import Foundation
import GrabberKit

extension AppModel {
    func recomputeBanner(_ snapshot: QueueSnapshot) {
        guard let reason = resolveBanner(Self.activeBannerReasons(snapshot.queueHalt)) else {
            bannerContent = nil
            return
        }
        let hosts = snapshot.hostRateSummary
            .filter { Self.isCircuitOpen($0.value.state) }
            .keys
            .map { SiteNames.display($0.canonical) }
            .sorted()
        bannerContent = bannerCopy(for: reason, circuitHosts: hosts) { [weak self] in
            await self?.resetAllCircuits()
        }
    }

    private static func activeBannerReasons(_ halt: QueueHaltReason?) -> Set<BannerReason> {
        switch halt {
        case .depMissing: [.depMissing]
        case .networkDown: [.networkDown]
        case .circuitOpen: [.circuitOpen]
        default: []
        }
    }

    private static func isCircuitOpen(_ state: RateState) -> Bool {
        if case .circuitOpen = state {
            return true
        }
        return false
    }
}
