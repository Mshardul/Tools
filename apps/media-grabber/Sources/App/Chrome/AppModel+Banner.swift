import Foundation
import GrabberKit

extension AppModel {
    func recomputeBanner(_ snapshot: QueueSnapshot) {
        let active = Self.activeBannerReasons(
            halt: snapshot.queueHalt,
            shieldStatus: snapshot.shieldStatus
        )
        guard let reason = resolveBanner(active) else {
            bannerContent = nil
            return
        }
        let hosts = snapshot.hostRateSummary
            .filter { Self.isCircuitOpen($0.value.state) }
            .keys
            .map { SiteNames.display($0.canonical) }
            .sorted()
        bannerContent = bannerCopy(for: reason, circuitHosts: hosts) { [weak self] in
            switch reason {
            case .circuitOpen:
                await self?.resetAllCircuits()
            case .potProviderDown:
                await self?.restartShield()
            default:
                break
            }
        }
    }

    private static func activeBannerReasons(
        halt: QueueHaltReason?,
        shieldStatus: ShieldStatus
    ) -> Set<BannerReason> {
        var reasons = haltReasons(halt)
        switch shieldStatus {
        case .running:
            break
        case .down, .missing:
            reasons.insert(.potProviderDown)
        }
        return reasons
    }

    private static func haltReasons(_ halt: QueueHaltReason?) -> Set<BannerReason> {
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
