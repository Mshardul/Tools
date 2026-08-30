import Foundation

extension DownloadEngine {
    // The Phase 4 (backoff) / Phase 6 (host cooldown) seam. No Phase 2 path calls this.
    func deferStart(_ id: UUID, until notBefore: Date) {
        deferrals.removeAll { $0.id == id }
        deferrals.append((id: id, notBefore: notBefore))
        deferrals.sort { $0.notBefore < $1.notBefore }
        armDeferralTask()
    }

    func deferStartForTest(_ id: UUID, until notBefore: Date) {
        deferStart(id, until: notBefore)
    }

    private func armDeferralTask() {
        deferralTask?.cancel()
        guard let earliest = deferrals.first?.notBefore else {
            deferralTask = nil
            return
        }
        let clock = dependencies.clock
        deferralTask = Task { [weak self] in
            await clock.sleep(until: earliest)
            await self?.fireDueDeferrals()
        }
    }

    private func fireDueDeferrals() {
        let now = dependencies.clock.now
        let due = deferrals.filter { $0.notBefore <= now }
        deferrals.removeAll { $0.notBefore <= now }
        deferralTask = nil
        if !due.isEmpty {
            evaluateSchedule()
        }
        armDeferralTask()
    }
}
