import Foundation

@MainActor
protocol AppUpdating: AnyObject {
    func start(automaticChecks: Bool)
    func setAutomaticChecks(_ enabled: Bool)
    func checkForUpdates()
}

@MainActor
final class IdleAppUpdating: AppUpdating {
    func start(automaticChecks _: Bool) {}
    func setAutomaticChecks(_: Bool) {}
    func checkForUpdates() {}
}
