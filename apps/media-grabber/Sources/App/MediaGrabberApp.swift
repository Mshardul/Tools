import SwiftUI

@main
struct MediaGrabberApp: App {
    var body: some Scene {
        WindowGroup {
            Text("MediaGrabber")
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentSize)
    }
}
