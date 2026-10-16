import Foundation

extension AppModel {
    private static let lastPromptedUpdateKey = "mg.lastPromptedUpdateVersion"

    // A dev build reports 0.0.0, which would always look outdated, so it never prompts.
    func checkForAppUpdateOnLaunch() async {
        guard prefs.autoCheckAppUpdates, appVersion != "0.0.0", !needsOnboarding else { return }
        let status = await appUpdateChecker.checkForUpdate(currentVersion: appVersion)
        guard case let .updateAvailable(version, releaseURL) = status,
              defaults.string(forKey: Self.lastPromptedUpdateKey) != version
        else { return }
        defaults.set(version, forKey: Self.lastPromptedUpdateKey)
        if await confirm(AppModelDialogs.updateAvailable(version: version, current: appVersion)) {
            openURLSink.open(releaseURL)
        }
    }
}
