import Foundation

extension AppModel {
    var hasGrabbedOnce: Bool {
        get { defaults.bool(forKey: "mg.hasGrabbedOnce") }
        set { defaults.set(newValue, forKey: "mg.hasGrabbedOnce") }
    }

    var showsTable: Bool {
        hasGrabbedOnce || !rowStore.rows.isEmpty
    }
}
