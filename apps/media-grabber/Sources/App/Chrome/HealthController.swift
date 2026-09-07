import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class HealthController {
    private(set) var chips: [HealthChip] = []

    func update(snapshot: QueueSnapshot, now _: Date) {
        var next: [HealthChip] = [
            shieldChip(snapshot.shieldStatus),
            onlineChip(snapshot.isOnline)
        ]
        if let cooldown = hostRateChip(snapshot.hostRateSummary) {
            next.append(cooldown)
        }
        chips = next
    }

    private func shieldChip(_ status: ShieldStatus) -> HealthChip {
        switch status {
        case .running:
            HealthChip(id: "shield", label: "shield", dot: .ok, interaction: .none)
        case .down, .missing:
            HealthChip(
                id: "shield",
                label: "shield · offline",
                dot: .attention,
                interaction: .refresh
            )
        }
    }

    private func onlineChip(_ online: Bool) -> HealthChip {
        HealthChip(
            id: "online",
            label: online ? "online" : "offline",
            dot: online ? .ok : .attention,
            interaction: .none
        )
    }

    private func hostRateChip(_ summary: [RateHost: HostRateDisplayState]) -> HealthChip? {
        guard !summary.isEmpty else { return nil }
        if summary.count == 1, let (host, display) = summary.first {
            return oneHostChip(host, display)
        }
        return HealthChip(
            id: "host-rate",
            label: "\(summary.count) sites cooling down",
            dot: .attention,
            interaction: .popover(.hostRate)
        )
    }

    private func oneHostChip(_ host: RateHost, _ display: HostRateDisplayState) -> HealthChip {
        let name = SiteNames.display(host.canonical)
        if case let .cooldown(until, _) = display.state {
            return HealthChip(
                id: "host-rate",
                label: name,
                dot: .attention,
                interaction: .popover(.hostRate),
                countdownUntil: until
            )
        }
        let label = isCircuitOpen(display.state) ? "\(name) — paused" : name
        return HealthChip(
            id: "host-rate",
            label: label,
            dot: .attention,
            interaction: .popover(.hostRate)
        )
    }

    private func isCircuitOpen(_ state: RateState) -> Bool {
        if case .circuitOpen = state {
            return true
        }
        return false
    }
}
