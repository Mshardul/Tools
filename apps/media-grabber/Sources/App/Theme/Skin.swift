import GrabberKit
import SwiftUI

enum MotifKind {
    case reel
    case orb
}

enum Skin {
    case tapeDeck
    case aurora

    init(_ kind: SkinKind) {
        switch kind {
        case .aurora: self = .aurora
        case .tapeDeck: self = .tapeDeck
        }
    }

    var displayFont: (CGFloat, Font.Weight) -> Font {
        { size, weight in Self.resolvedFont("Sora", size: size, weight: weight) }
    }

    var bodyFont: (CGFloat, Font.Weight) -> Font {
        { size, weight in Self.resolvedFont("Inter", size: size, weight: weight) }
    }

    var monoFont: (CGFloat, Font.Weight) -> Font {
        { size, weight in
            Self.resolvedFont(
                "JetBrains Mono",
                size: size,
                weight: weight,
                fallbackDesign: .monospaced
            )
        }
    }

    private static func resolvedFont(
        _ family: String,
        size: CGFloat,
        weight: Font.Weight,
        fallbackDesign: Font.Design = .default
    ) -> Font {
        #if canImport(AppKit)
            if NSFont(name: family, size: size) != nil {
                return Font.custom(family, size: size).weight(weight)
            }
        #endif
        return Font.system(size: size, weight: weight, design: fallbackDesign)
    }

    var windowRadius: CGFloat {
        self == .aurora ? 18 : 10
    }

    var cardRadius: CGFloat {
        self == .aurora ? 14 : 8
    }

    var controlRadius: CGFloat {
        self == .aurora ? 9 : 6
    }

    var pillRadius: CGFloat {
        self == .aurora ? 20 : 14
    }

    var chipRadius: CGFloat {
        self == .aurora ? 7 : 5
    }

    var hairlineWidth: CGFloat {
        1
    }

    var motif: MotifKind {
        self == .aurora ? .orb : .reel
    }
}

enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 22
    static let s6: CGFloat = 30
    static let s7: CGFloat = 44
}
