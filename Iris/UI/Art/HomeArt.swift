// Generated from the home screen design artwork; the title layer is Iris lettering.

import SwiftUI

/// Layers of the home screen artboard, bottom to top, in artboard points (720 × 1600, y down).
enum HomeArt {
    static let artboard = CGRect(x: 0, y: 0, width: 720, height: 1600)

    /// Illustrator "Layer 2".
    static let background = ArtLayer(name: "Layer 2", fills: [
        ArtFill(color: Color(red: 1, green: 0.435, blue: 0.212), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 0, y: 1600))
            p.addLine(to: CGPoint(x: 719.457, y: 1600))
            p.addLine(to: CGPoint(x: 719.457, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }),
    ])

    /// Illustrator "Layer 3".
    static let monster = ArtLayer(name: "Layer 3", fills: [
        ArtFill(color: Color(red: 1, green: 0.882, blue: 0), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: -15.107, y: 1053.963))
            p.addCurve(to: CGPoint(x: 301.821, y: 600.986), control1: CGPoint(x: 11.306, y: 864.491), control2: CGPoint(x: 132.876, y: 690.734))
            p.addCurve(to: CGPoint(x: 357.56, y: 666.058), control1: CGPoint(x: 336.732, y: 582.44), control2: CGPoint(x: 381.248, y: 634.408))
            p.addCurve(to: CGPoint(x: 449.44, y: 599.797), control1: CGPoint(x: 355.102, y: 621.239), control2: CGPoint(x: 407.689, y: 583.315))
            p.addCurve(to: CGPoint(x: 471.278, y: 710.952), control1: CGPoint(x: 491.19, y: 616.28), control2: CGPoint(x: 503.69, y: 679.899))
            p.addCurve(to: CGPoint(x: 619.781, y: 712.434), control1: CGPoint(x: 493.332, y: 650.137), control2: CGPoint(x: 598.945, y: 651.191))
            p.addCurve(to: CGPoint(x: 747.055, y: 1698.814), control1: CGPoint(x: 727.272, y: 1028.38), control2: CGPoint(x: 770.826, y: 1365.931))
            p.addCurve(to: CGPoint(x: 380.207, y: 2013.772), control1: CGPoint(x: 734.548, y: 1873.959), control2: CGPoint(x: 555.202, y: 1999.324))
            p.addCurve(to: CGPoint(x: -127.286, y: 1893.424), control1: CGPoint(x: 205.211, y: 2028.22), control2: CGPoint(x: 35.12, y: 1960.182))
        }),
    ])

    /// Illustrator "Layer 4".
    static let eyeWhite = ArtLayer(name: "Layer 4", fills: [
        ArtFill(color: Color(red: 0.98, green: 0.976, blue: 0.949), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 374.137, y: 892.775))
            p.addCurve(to: CGPoint(x: 244.937, y: 896.354), control1: CGPoint(x: 339.242, y: 860.697), control2: CGPoint(x: 279.44, y: 863.856))
            p.addCurve(to: CGPoint(x: 222.508, y: 1027.574), control1: CGPoint(x: 210.435, y: 928.853), control2: CGPoint(x: 202.577, y: 984.569))
            p.addCurve(to: CGPoint(x: 333.806, y: 1106.329), control1: CGPoint(x: 242.439, y: 1070.579), control2: CGPoint(x: 286.852, y: 1099.85))
            p.addCurve(to: CGPoint(x: 468.055, y: 1070.765), control1: CGPoint(x: 380.76, y: 1112.806), control2: CGPoint(x: 429.287, y: 1098.036))
            p.addCurve(to: CGPoint(x: 498.73, y: 948.564), control1: CGPoint(x: 505.488, y: 1044.436), control2: CGPoint(x: 519.29, y: 989.452))
            p.addCurve(to: CGPoint(x: 382.343, y: 900.31), control1: CGPoint(x: 478.17, y: 907.676), control2: CGPoint(x: 425.803, y: 885.966))
        }),
    ])

    /// Illustrator "Layer 5".
    static let iris = ArtLayer(name: "Layer 5", fills: [
        ArtFill(color: Color(red: 0, green: 0.584, blue: 1), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 302.75, y: 989.063))
            p.addCurve(to: CGPoint(x: 360, y: 931.813), control1: CGPoint(x: 302.75, y: 957.445), control2: CGPoint(x: 328.382, y: 931.813))
            p.addCurve(to: CGPoint(x: 417.25, y: 989.063), control1: CGPoint(x: 391.618, y: 931.813), control2: CGPoint(x: 417.25, y: 957.445))
            p.addCurve(to: CGPoint(x: 360, y: 1046.313), control1: CGPoint(x: 417.25, y: 1020.681), control2: CGPoint(x: 391.618, y: 1046.313))
            p.addCurve(to: CGPoint(x: 302.75, y: 989.063), control1: CGPoint(x: 328.382, y: 1046.313), control2: CGPoint(x: 302.75, y: 1020.681))
        }),
    ])

    /// Illustrator "Layer 6".
    static let pupil = ArtLayer(name: "Layer 6", fills: [
        ArtFill(color: Color(red: 0.012, green: 0.102, blue: 0.161), evenOdd: false, path: Path { p in
            p.move(to: CGPoint(x: 319.75, y: 989.063))
            p.addCurve(to: CGPoint(x: 360, y: 948.813), control1: CGPoint(x: 319.75, y: 966.834), control2: CGPoint(x: 337.771, y: 948.813))
            p.addCurve(to: CGPoint(x: 400.25, y: 989.063), control1: CGPoint(x: 382.229, y: 948.813), control2: CGPoint(x: 400.25, y: 966.834))
            p.addCurve(to: CGPoint(x: 360, y: 1029.313), control1: CGPoint(x: 400.25, y: 1011.292), control2: CGPoint(x: 382.229, y: 1029.313))
            p.addCurve(to: CGPoint(x: 319.75, y: 989.063), control1: CGPoint(x: 337.771, y: 1029.313), control2: CGPoint(x: 319.75, y: 1011.292))
        }),
    ])

    /// The "IRIS" wordmark, set where the artwork's title sat (it replaces that layer).
    static let title = IrisLettering.layer(
        name: "Title", text: "IRIS",
        in: CGRect(x: 76.6, y: 270.9, width: 572.0, height: 126.3),
        color: Color(red: 1, green: 1, blue: 1)
    )

    /// Every layer in drawing order.
    static let layers = [background, monster, eyeWhite, iris, pupil, title]
}
