import AppKit
import GrabberKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var quitCoordinator: QuitCoordinator?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let quitCoordinator else {
            return .terminateNow
        }
        Task {
            let shouldQuit = await quitCoordinator.requestTerminate()
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }
}
