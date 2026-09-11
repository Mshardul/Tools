import Foundation
import UniformTypeIdentifiers

@MainActor
public enum ShareExtractor {
    public static func extractURL(from items: [NSExtensionItem]) async -> URL? {
        for item in items {
            guard let attachments = item.attachments else { continue }
            if let url = await firstURL(in: attachments) {
                return url
            }
            if let text = await firstPlainText(in: attachments), let url = LinkExtractor.extract(from: text) {
                return url
            }
        }
        return nil
    }

    // loadItem(forTypeIdentifier:) returns raw coder output, not the bridged type — loadObject coerces correctly.
    private static func firstURL(in attachments: [NSItemProvider]) async -> URL? {
        for provider in attachments where provider.canLoadObject(ofClass: URL.self) {
            if let url = await loadURLObject(from: provider) {
                return url
            }
        }
        return nil
    }

    private static func firstPlainText(in attachments: [NSItemProvider]) async -> String? {
        for provider in attachments where provider.canLoadObject(ofClass: String.self) {
            if let text = await loadStringObject(from: provider) {
                return text
            }
        }
        return nil
    }

    private static func loadURLObject(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }

    private static func loadStringObject(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }
}
