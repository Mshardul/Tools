import Foundation
import UserNotifications

@MainActor
protocol NotificationRouting {
    func notifyJobFailed(title: String, reason: String) async
}

@MainActor
final class NotificationRouter: NotificationRouting {
    private var permissionRequested = false

    func notifyJobFailed(title: String, reason: String) async {
        await requestPermissionIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "\(title) failed"
        content.body = reason
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func requestPermissionIfNeeded() async {
        guard !permissionRequested else { return }
        permissionRequested = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert])
    }
}
