import AppKit

protocol SharePresenting {
    @MainActor func share(data: Data, filename: String)
}

struct SharePresenter: SharePresenting {
    @MainActor
    func share(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }
}
