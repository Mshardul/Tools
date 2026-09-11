import AppKit
import Foundation
import GrabberKit

final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task {
            await handleShare()
        }
    }

    private func handleShare() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        guard let url = await ShareExtractor.extractURL(from: items),
              let schemeURL = makeSchemeURL(for: url)
        else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        NSWorkspace.shared.open(schemeURL)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func makeSchemeURL(for url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "mediagrabber"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }
}
