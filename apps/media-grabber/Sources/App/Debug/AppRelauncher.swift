import AppKit
import Foundation

protocol RelaunchProcessLaunching {
    func launch(executablePath: String, arguments: [String])
}

struct SystemProcessLauncher: RelaunchProcessLaunching {
    func launch(executablePath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        try? process.run()
    }
}

@MainActor
struct AppRelauncher {
    private let launcher: RelaunchProcessLaunching
    private let terminate: () -> Void

    init(
        launcher: RelaunchProcessLaunching = SystemProcessLauncher(),
        terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.launcher = launcher
        self.terminate = terminate
    }

    func relaunch(withExtraArguments extraArguments: [String]) {
        guard let executablePath = Bundle.main.executablePath else { return }
        launcher.launch(executablePath: executablePath, arguments: extraArguments)
        terminate()
    }
}
