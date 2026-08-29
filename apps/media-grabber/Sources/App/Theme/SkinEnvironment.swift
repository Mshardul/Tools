import GrabberKit
import SwiftUI

struct ResolvedTheme {
    let skin: Skin
    let palette: PaletteTokens

    init(skin: Skin, palette: PaletteTokens) {
        self.skin = skin
        self.palette = palette
    }

    init(skinKind: SkinKind, paletteKind: PaletteKind) {
        skin = Skin(skinKind)
        palette = MediaGrabber.palette(for: paletteKind)
    }

    static let auroraMintIris = ResolvedTheme(
        skin: Skin(.aurora),
        palette: PaletteTokens.auroraMintIris
    )
}

extension EnvironmentValues {
    @Entry var theme: ResolvedTheme = .auroraMintIris
}

extension View {
    func theme(_ theme: ResolvedTheme) -> some View {
        environment(\.theme, theme)
    }
}
