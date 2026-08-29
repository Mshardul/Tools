import SwiftUI

#if canImport(AppKit)
    import AppKit

    // Persists window size/position across launches; no SwiftUI equivalent on macOS 14.
    struct WindowFrameAutosave: NSViewRepresentable {
        let name: String

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { [weak view] in
                view?.window?.setFrameAutosaveName(name)
            }
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}
    }
#else
    struct WindowFrameAutosave: View {
        let name: String
        var body: some View {
            Color.clear
        }
    }
#endif
