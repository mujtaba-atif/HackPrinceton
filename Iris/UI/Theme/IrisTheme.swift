import SwiftUI

enum IrisTheme {
    static let background = Color(red: 0.055, green: 0.071, blue: 0.075)
    static let surface = Color(red: 0.086, green: 0.110, blue: 0.116)
    static let raisedSurface = Color(red: 0.112, green: 0.143, blue: 0.149)
    static let accent = Color(red: 0.286, green: 0.902, blue: 0.820)
    static let accentSoft = Color(red: 0.286, green: 0.902, blue: 0.820).opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.74)
    static let hairline = Color.white.opacity(0.12)

    static let screenPadding: CGFloat = 24
    static let controlCornerRadius: CGFloat = 20
}

extension View {
    func irisScreenBackground() -> some View {
        background(IrisTheme.background.ignoresSafeArea())
    }
}

