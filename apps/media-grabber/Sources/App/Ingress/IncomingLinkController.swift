import Foundation
import GrabberKit
import Observation

@MainActor
@Observable
final class IncomingLinkController {
    static let pollInterval: TimeInterval = 0.75

    private let home: IncomingLinkHome
    private let pasteboard: any PasteboardReading & PasteboardWriting

    private var lastHandledChangeCount: Int?
    private var lastHandledURL: String?
    private var ignoredChangeCount: Int?
    private var detectionGeneration = 0

    init(
        home: IncomingLinkHome,
        pasteboard: any PasteboardReading & PasteboardWriting = SystemPasteboard()
    ) {
        self.home = home
        self.pasteboard = pasteboard
    }

    // MARK: - Direct ingress

    func handlePlainText(_ raw: String) async {
        guard let url = LinkExtractor.extract(from: raw) else { return }
        await ingest(url)
    }

    func handleOpenURL(_ url: URL) async {
        switch IncomingLinkScheme.openURL(from: url) {
        case let .success(webURL):
            await ingest(webURL)
        case .failure:
            _ = await home.confirm(AppModelDialogs.incomingLinkSchemeFailureNotice())
        }
    }

    // MARK: - Clipboard

    func markAppPasteboardWrite() {
        ignoredChangeCount = pasteboard.changeCount + 1
    }

    func setClipboardDetectionEnabled(_ enabled: Bool) async {
        detectionGeneration += 1
        if enabled {
            await sniffClipboard()
        }
    }

    func applicationDidBecomeActive() async {
        await sniffClipboard()
    }

    func pollPasteboard() async {
        await sniffClipboard()
    }

    private func sniffClipboard() async {
        guard home.detectClipboardLinks else { return }
        let change = pasteboard.changeCount
        if let ignored = ignoredChangeCount, change == ignored {
            return
        }
        guard let raw = pasteboard.readString(),
              let url = LinkExtractor.extract(from: raw) else { return }
        if change == lastHandledChangeCount, url.absoluteString == lastHandledURL {
            return
        }
        lastHandledChangeCount = change
        lastHandledURL = url.absoluteString
        await ingestFromClipboard(url, generation: detectionGeneration)
    }

    // MARK: - Policy

    private func ingest(_ url: URL) async {
        guard await confirmedForBusy(url) else { return }
        await home.applyIncomingURL(url)
    }

    private func ingestFromClipboard(_ url: URL, generation: Int) async {
        guard await confirmedForBusy(url), generation == detectionGeneration else { return }
        await home.applyIncomingURL(url)
    }

    private func confirmedForBusy(_ url: URL) async -> Bool {
        guard home.isHomeBusy else { return true }
        return await home.confirm(AppModelDialogs.incomingLinkBusyConfirmation(url: url))
    }
}
