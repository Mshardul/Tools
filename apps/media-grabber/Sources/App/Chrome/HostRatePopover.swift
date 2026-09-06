import GrabberKit
import SwiftUI

struct HostRatePopover: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let summary = appModel.hostRateSummary
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(sortedHosts(summary), id: \.self) { host in
                if let display = summary[host] {
                    row(host, display)
                }
            }
            if summary.values.contains(where: isCircuitOpen) {
                Button("Retry all") {
                    Task { await appModel.resetAllCircuits() }
                }
            }
        }
        .padding(Spacing.s3)
        .frame(minWidth: 240)
    }

    private func sortedHosts(_ summary: [RateHost: HostRateDisplayState]) -> [RateHost] {
        summary.keys.sorted { $0.canonical < $1.canonical }
    }

    private func row(_ host: RateHost, _ display: HostRateDisplayState) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(SiteNames.display(host.canonical)).font(.headline)
            detailText(display)
            if isCircuitOpen(display) {
                Button("Retry now") {
                    Task { await appModel.resetCircuit(host: host) }
                }
            }
        }
    }

    @ViewBuilder
    private func detailText(_ display: HostRateDisplayState) -> some View {
        let suffix = display.concurrencyReducedToOne ? " · concurrency reduced to 1" : ""
        switch display.state {
        case let .cooldown(until, _):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Cooling down — \(CountdownFormat.mmss(until: until, now: context.date))\(suffix)")
            }
        case .circuitOpen:
            Text("Rate-limited — paused\(suffix)")
        case .normal:
            EmptyView()
        }
    }

    private func isCircuitOpen(_ display: HostRateDisplayState) -> Bool {
        if case .circuitOpen = display.state {
            return true
        }
        return false
    }
}
