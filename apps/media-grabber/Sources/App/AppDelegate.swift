import AppKit
import GrabberKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var quitCoordinator: QuitCoordinator?
    var incomingLinks: IncomingLinkController?

    private var clipboardPollTimer: Timer?

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

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.servicesProvider = self
    }

    func applicationDidBecomeActive(_: Notification) {
        Task { await incomingLinks?.applicationDidBecomeActive() }
        startClipboardPolling()
    }

    func applicationDidResignActive(_: Notification) {
        stopClipboardPolling()
    }

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await incomingLinks?.handleOpenURL(url) }
        }
    }

    @objc
    func downloadWithMediaGrabber(
        _ pboard: NSPasteboard,
        userData _: String?,
        error _: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string) ?? pboard.string(forType: .URL) else {
            return
        }
        Task { await incomingLinks?.handlePlainText(text) }
    }

    private func startClipboardPolling() {
        guard clipboardPollTimer == nil else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: IncomingLinkController.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in await self?.incomingLinks?.pollPasteboard() }
        }
        clipboardPollTimer = timer
    }

    private func stopClipboardPolling() {
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = nil
    }
}
