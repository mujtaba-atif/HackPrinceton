// Generated from the main screen design artwork; the two button labels are Iris lettering.

import SwiftUI

/// Layers of the MainScreen.ai artboard, bottom to top, in artboard points (720 × 1600, y down).
enum MainArt {
    static let artboard = CGRect(x: 0, y: 0, width: 720, height: 1600)

    /// Illustrator "Layer 1".
    static let background = ArtLayer(name: "Layer 1", fills: [
        ArtFill(color: Color(red: 0.169, green: 0.729, blue: 1), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 0, y: 1600))
            p.addLine(to: CGPoint(x: 720, y: 1600))
            p.addLine(to: CGPoint(x: 720, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }),
    ])

    /// Illustrator "Layer 2".
    static let findCard = ArtLayer(name: "Layer 2", fills: [
        ArtFill(color: Color(red: 0, green: 0.098, blue: 0.651), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 55, y: 887.987))
            p.addLine(to: CGPoint(x: 55, y: 575.892))
            p.addCurve(to: CGPoint(x: 75.953, y: 554.94), control1: CGPoint(x: 55, y: 564.32), control2: CGPoint(x: 64.381, y: 554.94))
            p.addLine(to: CGPoint(x: 644.047, y: 554.94))
            p.addCurve(to: CGPoint(x: 665, y: 575.892), control1: CGPoint(x: 655.619, y: 554.94), control2: CGPoint(x: 665, y: 564.32))
            p.addLine(to: CGPoint(x: 665, y: 887.987))
            p.addCurve(to: CGPoint(x: 644.047, y: 908.94), control1: CGPoint(x: 665, y: 899.559), control2: CGPoint(x: 655.619, y: 908.94))
            p.addLine(to: CGPoint(x: 75.953, y: 908.94))
            p.addCurve(to: CGPoint(x: 55, y: 887.987), control1: CGPoint(x: 64.381, y: 908.94), control2: CGPoint(x: 55, y: 899.559))
        }),
    ])

    /// "LOCATE", drawn sideways on the Locate card where the artwork's label sat.
    static let findLabel = IrisLettering.layer(
        name: "Locate label", text: "LOCATE",
        in: CGRect(x: 108.8, y: 579.4, width: 90.9, height: 301.1),
        color: Color(red: 1, green: 1, blue: 1), orientation: .upward
    )

    /// Illustrator "Layer 3".
    static let findEyes = ArtLayer(name: "Layer 3", fills: [
        ArtFill(color: Color(red: 1, green: 1, blue: 1), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 353.197, y: 651.312))
            p.addCurve(to: CGPoint(x: 257.647, y: 712.725), control1: CGPoint(x: 312.213, y: 643.202), control2: CGPoint(x: 267.445, y: 671.975))
            p.addCurve(to: CGPoint(x: 314.773, y: 811.107), control1: CGPoint(x: 247.848, y: 753.475), control2: CGPoint(x: 274.613, y: 799.569))
            p.addCurve(to: CGPoint(x: 415.129, y: 757.97), control1: CGPoint(x: 354.933, y: 822.645), control2: CGPoint(x: 401.952, y: 797.749))
            p.addCurve(to: CGPoint(x: 366.444, y: 655.118), control1: CGPoint(x: 428.305, y: 718.191), control2: CGPoint(x: 405.495, y: 670.002))
        }),
        ArtFill(color: Color(red: 1, green: 1, blue: 1), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 562.718, y: 660.838))
            p.addCurve(to: CGPoint(x: 457.671, y: 700.52), control1: CGPoint(x: 524.805, y: 644.006), control2: CGPoint(x: 475.111, y: 662.778))
            p.addCurve(to: CGPoint(x: 495.354, y: 806.618), control1: CGPoint(x: 440.23, y: 738.262), control2: CGPoint(x: 458.057, y: 788.453))
            p.addCurve(to: CGPoint(x: 601.731, y: 770.683), control1: CGPoint(x: 532.65, y: 824.783), control2: CGPoint(x: 582.974, y: 807.783))
            p.addCurve(to: CGPoint(x: 567.805, y: 663.316), control1: CGPoint(x: 620.489, y: 733.582), control2: CGPoint(x: 604.44, y: 682.791))
        }),
    ])

    /// Illustrator "Layer 4".
    static let findPupils = ArtLayer(name: "Layer 4", fills: [
        ArtFill(color: Color(red: 0, green: 0, blue: 0), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 335.765, y: 734.284))
            p.addCurve(to: CGPoint(x: 372.984, y: 696.935), control1: CGPoint(x: 335.765, y: 713.658), control2: CGPoint(x: 352.429, y: 696.935))
            p.addCurve(to: CGPoint(x: 410.204, y: 734.284), control1: CGPoint(x: 393.54, y: 696.935), control2: CGPoint(x: 410.204, y: 713.658))
            p.addCurve(to: CGPoint(x: 372.984, y: 771.634), control1: CGPoint(x: 410.204, y: 754.911), control2: CGPoint(x: 393.54, y: 771.634))
            p.addCurve(to: CGPoint(x: 335.765, y: 734.284), control1: CGPoint(x: 352.429, y: 771.634), control2: CGPoint(x: 335.765, y: 754.911))
        }),
        ArtFill(color: Color(red: 0, green: 0, blue: 0), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 526.796, y: 734.284))
            p.addCurve(to: CGPoint(x: 564.015, y: 696.935), control1: CGPoint(x: 526.796, y: 713.658), control2: CGPoint(x: 543.46, y: 696.935))
            p.addCurve(to: CGPoint(x: 601.235, y: 734.284), control1: CGPoint(x: 584.571, y: 696.935), control2: CGPoint(x: 601.235, y: 713.658))
            p.addCurve(to: CGPoint(x: 564.015, y: 771.634), control1: CGPoint(x: 601.235, y: 754.911), control2: CGPoint(x: 584.571, y: 771.634))
            p.addCurve(to: CGPoint(x: 526.796, y: 734.284), control1: CGPoint(x: 543.46, y: 771.634), control2: CGPoint(x: 526.796, y: 754.911))
        }),
    ])

    /// Illustrator "Layer 6".
    static let analyzeCard = ArtLayer(name: "Layer 6", fills: [
        ArtFill(color: Color(red: 1, green: 1, blue: 1), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 55, y: 1309.426))
            p.addLine(to: CGPoint(x: 55, y: 997.331))
            p.addCurve(to: CGPoint(x: 75.953, y: 976.379), control1: CGPoint(x: 55, y: 985.759), control2: CGPoint(x: 64.381, y: 976.379))
            p.addLine(to: CGPoint(x: 644.047, y: 976.379))
            p.addCurve(to: CGPoint(x: 665, y: 997.331), control1: CGPoint(x: 655.619, y: 976.379), control2: CGPoint(x: 665, y: 985.759))
            p.addLine(to: CGPoint(x: 665, y: 1309.426))
            p.addCurve(to: CGPoint(x: 644.047, y: 1330.379), control1: CGPoint(x: 665, y: 1320.998), control2: CGPoint(x: 655.619, y: 1330.379))
            p.addLine(to: CGPoint(x: 75.953, y: 1330.379))
            p.addCurve(to: CGPoint(x: 55, y: 1309.426), control1: CGPoint(x: 64.381, y: 1330.379), control2: CGPoint(x: 55, y: 1320.998))
        }),
    ])

    /// "EXPLORE", drawn sideways like the artwork's label (the Explore face turns it upright).
    static let analyzeLabel = IrisLettering.layer(
        name: "Explore label", text: "EXPLORE",
        in: CGRect(x: 126.5, y: 992.3, width: 48.7, height: 323.6),
        color: Color(red: 0, green: 0.098, blue: 0.651), orientation: .upward
    )

    /// Illustrator "Layer 8".
    static let magnifier = ArtLayer(name: "Layer 8", fills: [
        ArtFill(color: Color(red: 0.847, green: 0.851, blue: 0.89), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 300.941, y: 1136.959))
            p.addCurve(to: CGPoint(x: 427.272, y: 1009.855), control1: CGPoint(x: 300.941, y: 1066.762), control2: CGPoint(x: 357.501, y: 1009.855))
            p.addCurve(to: CGPoint(x: 553.603, y: 1136.959), control1: CGPoint(x: 497.043, y: 1009.855), control2: CGPoint(x: 553.603, y: 1066.762))
            p.addCurve(to: CGPoint(x: 427.272, y: 1264.063), control1: CGPoint(x: 553.603, y: 1207.156), control2: CGPoint(x: 497.043, y: 1264.063))
            p.addCurve(to: CGPoint(x: 300.941, y: 1136.959), control1: CGPoint(x: 357.501, y: 1264.063), control2: CGPoint(x: 300.941, y: 1207.156))
        }),
        ArtFill(color: Color(red: 0.847, green: 0.851, blue: 0.89), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 561.411, y: 1387.856))
            p.addLine(to: CGPoint(x: 424.523, y: 1176.208))
            p.addLine(to: CGPoint(x: 464.054, y: 1150.327))
            p.addLine(to: CGPoint(x: 600.942, y: 1361.975))
            p.closeSubpath()
        }),
    ])

    /// Illustrator "Layer 9".
    static let magnifierLens = ArtLayer(name: "Layer 9", fills: [
        ArtFill(color: Color(red: 1, green: 1, blue: 1), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 318.628, y: 1136.959))
            p.addCurve(to: CGPoint(x: 427.273, y: 1027.65), control1: CGPoint(x: 318.628, y: 1076.589), control2: CGPoint(x: 367.27, y: 1027.65))
            p.addCurve(to: CGPoint(x: 535.917, y: 1136.959), control1: CGPoint(x: 487.275, y: 1027.65), control2: CGPoint(x: 535.917, y: 1076.589))
            p.addCurve(to: CGPoint(x: 427.273, y: 1246.268), control1: CGPoint(x: 535.917, y: 1197.329), control2: CGPoint(x: 487.275, y: 1246.268))
            p.addCurve(to: CGPoint(x: 318.628, y: 1136.959), control1: CGPoint(x: 367.27, y: 1246.268), control2: CGPoint(x: 318.628, y: 1197.329))
        }),
    ])

    /// Every layer in drawing order.
    static let layers = [background, findCard, findLabel, findEyes, findPupils, analyzeCard, analyzeLabel, magnifier, magnifierLens]
}
