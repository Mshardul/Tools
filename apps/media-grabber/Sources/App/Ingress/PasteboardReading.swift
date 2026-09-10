import Foundation

#if canImport(AppKit)
    import AppKit
#endif

protocol PasteboardReading: Sendable {
    var changeCount: Int { get }
    func readString() -> String?
}

protocol PasteboardWriting: Sendable {
    func writeString(_ string: String)
}

#if canImport(AppKit)
    struct SystemPasteboard: PasteboardReading, PasteboardWriting {
        var changeCount: Int {
            NSPasteboard.general.changeCount
        }

        func readString() -> String? {
            NSPasteboard.general.string(forType: .string)
        }

        func writeString(_ string: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }
#endif
