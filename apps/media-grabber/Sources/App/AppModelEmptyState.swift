import Foundation

extension AppModel {
    var hasGrabbedOnce: Bool {
        get { defaults.bool(forKey: "mg.hasGrabbedOnce") }
        set { defaults.set(newValue, forKey: "mg.hasGrabbedOnce") }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "mg.hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "mg.hasCompletedOnboarding") }
    }

    func completeOnboarding() async {
        hasCompletedOnboarding = true
        await onboardingFinished()
    }

    var showsTable: Bool {
        hasGrabbedOnce || !rowStore.rows.isEmpty
    }
}
