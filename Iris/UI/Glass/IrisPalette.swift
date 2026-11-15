import SwiftUI

/// The shared blue palette of the Iris design (`Design/Iris/assets.json`, `tokens`).
enum IrisPalette {
    static let navy = Color(hex: 0x123A73)
    static let deep = Color(hex: 0x092653)
    static let blue = Color(hex: 0x297FDB)
    static let sky = Color(hex: 0x72C7F5)
    static let ice = Color(hex: 0xE7F5FF)
    static let white = Color(hex: 0xFAFCFF)
    static let ink = Color(hex: 0x061B37)
    static let water = Color(hex: 0x3299E3)
    static let glass = Color(hex: 0xB5DEFA)

    /// The four colours sprinkles and confetti cycle through.
    static let confetti = [sky, glass, white, water]
}

extension Color {
    /// `0xRRGGBB`, with an optional alpha (CSS `#RRGGBBAA` is `Color(hex: 0xRRGGBB, alpha: 0xAA / 255)`).
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// CSS `#RRGGBBAA`.
    init(rgba: UInt32) {
        self.init(hex: rgba >> 8, alpha: Double(rgba & 0xFF) / 255)
    }
}

/// Nunito and Nunito Sans (SIL OFL, bundled in `Resources/Fonts` and registered by `UIAppFonts`).
enum IrisFont {
    enum Weight {
        case semibold, bold, extraBold, black
    }

    /// Nunito, the rounded face used for most text.
    static func nunito(_ size: CGFloat, _ weight: Weight = .bold) -> Font {
        let name = switch weight {
        case .semibold: "Nunito-SemiBold"
        case .bold: "Nunito-Bold"
        case .extraBold: "Nunito-ExtraBold"
        case .black: "Nunito-Black"
        }
        return .custom(name, fixedSize: size)
    }

    /// Nunito Sans, for the options question and the card titles. Black isn't bundled; it falls back to
    /// ExtraBold, as the design's own font files do.
    static func nunitoSans(_ size: CGFloat, _ weight: Weight = .bold) -> Font {
        let name = switch weight {
        case .semibold, .bold: "NunitoSans-Bold"
        case .extraBold, .black: "NunitoSans-ExtraBold"
        }
        return .custom(name, fixedSize: size)
    }
}
