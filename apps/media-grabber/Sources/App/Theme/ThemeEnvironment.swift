import GrabberKit
import SwiftUI

extension EnvironmentValues {
    @Entry var theme = Theme(themeKind: .aurora, paletteKind: .auroraMintIris)
}

extension View {
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }
}
