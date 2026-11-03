import Foundation
import GrabberKit

extension AppModel {
    func submitPasscode(_ raw: String) async {
        let passcode = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !passcode.isEmpty, let prompt = passcodeNeeded else { return }
        isPasscodeSheetShown = false
        switch prompt.target {
        case let .link(url):
            await engine.setPasscode(passcode, for: url)
            await resolvePasted(url, supersede: true)
        case let .job(id):
            await engine.retryWithPasscode(id, passcode: passcode)
            passcodeNeeded = nil
        }
    }

    func cancelPasscodePrompt() {
        isPasscodeSheetShown = false
    }

    func presentPasscodePrompt(forJob id: UUID) {
        let snapshot = rowStore.rows.first { $0.id == id }?.snapshot
        passcodeNeeded = PasscodePrompt(
            target: .job(id),
            url: snapshot?.url ?? "",
            wasRejected: snapshot?.state == .failed(.passcodeRejected)
        )
        isPasscodeSheetShown = true
    }

    func presentPasscodePrompt(forLink url: String, wasRejected: Bool) {
        passcodeNeeded = PasscodePrompt(target: .link(url), url: url, wasRejected: wasRejected)
        isPasscodeSheetShown = true
    }

    func resetPasscodePrompt() {
        passcodeNeeded = nil
        isPasscodeSheetShown = false
    }
}
