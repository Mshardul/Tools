import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class ShieldSetupController {
    enum State: Equatable {
        case idle
        case working(String)
        case done
        case needsHomebrew
        case failed(detail: String)
    }

    enum ProbePrompt: Equatable {
        case setUp
        case restart
    }

    var isPresented = false
    var probePrompt: ProbePrompt?
    private(set) var state: State = .idle

    @ObservationIgnored var onInstalled: (() async -> Void)?

    private let installer: ShieldInstaller
    private let restart: () async -> Bool
    private let openURL: OpenURLSink

    init(installer: ShieldInstaller, restart: @escaping () async -> Bool, openURL: OpenURLSink) {
        self.installer = installer
        self.restart = restart
        self.openURL = openURL
    }

    var isWorking: Bool {
        if case .working = state {
            return true
        }
        return false
    }

    func present() {
        if !isWorking {
            state = .idle
        }
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    func openHomebrewSite() {
        if let url = URL(string: "https://brew.sh") {
            openURL.open(url)
        }
    }

    func run() async {
        guard !isWorking else { return }
        state = .working("")
        let outcome = await installer.install { [weak self] text in
            Task { @MainActor in
                if self?.isWorking == true {
                    self?.state = .working(text)
                }
            }
        }
        switch outcome {
        case .installed:
            await finishInstall()
        case .needsHomebrew:
            state = .needsHomebrew
        case let .failed(detail):
            state = .failed(detail: detail)
        }
    }

    private func finishInstall() async {
        if await restart() {
            state = .done
            probePrompt = nil
            await onInstalled?()
        } else {
            state = .failed(detail: "installed, but the shield did not start")
        }
    }
}
