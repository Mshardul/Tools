import Foundation

extension DownloadEngine {
    // The deferred-start seam — backoff and host-cooldown both defer through here by Date.
    func deferStart(_ id: UUID, until notBefore: Date) {
        deferrals.removeAll { $0.id == id }
        deferrals.append((id: id, notBefore: notBefore))
        deferrals.sort { $0.notBefore < $1.notBefore }
        armDeferralTask()
    }

    func deferStartForTest(_ id: UUID, until notBefore: Date) {
        deferStart(id, until: notBefore)
    }

    func cancelDeferral(_ id: UUID) {
        deferrals.removeAll { $0.id == id }
        armDeferralTask()
    }

    func cancelDeferralForTest(_ id: UUID) {
        cancelDeferral(id)
    }

    func enterCooldownForTest(_ id: UUID, until: Date) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        job.state = .cooldown(until: until)
        job.cooldownUntil = until
        deferStart(id, until: until)
        bump()
        emitSnapshot()
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
        var flipped = false
        for entry in due {
            flipped = resumeIfCooldownElapsed(entry.id, now: now) || flipped
        }
        if !due.isEmpty {
            if flipped {
                bump()
                emitSnapshot()
            }
            evaluateSchedule()
        }
        armDeferralTask()
    }

    private func resumeIfCooldownElapsed(_ id: UUID, now: Date) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else { return false }
        guard case let .cooldown(until) = job.state, until <= now else { return false }
        job.state = .queued
        job.cooldownUntil = nil
        return true
    }
}
