import SwiftUI

/// The welcome → options transition: a sheet of blue glass sweeps across from the left, leaning into the
/// motion and straightening as it covers the screen (`glass-wipe`, 0.92 s). `onCovered` fires at 0.85 s,
/// when the next screen should take its place. Under reduced motion the sheet is simply there.
struct GlassWipe: View {
    var onCovered: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    private static let duration = 0.92
    private static let curve = Bezier(0.45, 0, 0.2, 1)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let p = reduceMotion ? 1 : Self.curve(min(1, timeline.date.timeIntervalSince(started) / Self.duration))
                let width = geo.size.width * 1.3
                // left: -140% → -10% of the screen; skewX(-12°) → 0.
                let left = geo.size.width * (-1.4 + 1.3 * p)
                let skew = tan(-12 * (1 - p) * .pi / 180)
                sheet(width: width, height: geo.size.height * 1.1)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: skew, d: 1, tx: -skew * geo.size.height * 0.55, ty: 0))
                    .offset(x: left, y: geo.size.height * -0.05)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .accessibilityHidden(true)
        .task {
            started = .now
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.85))
            onCovered()
        }
    }

    private func sheet(width: CGFloat, height: CGFloat) -> some View {
        let shape = WipeEdge()
        return shape
            .fill(LinearGradient(colors: [IrisPalette.glass, Color(rgba: 0x3299E3E6)],
                                 startPoint: UnitPoint(x: 0, y: 0.45), endPoint: UnitPoint(x: 1, y: 0.55)))
            .background(.ultraThinMaterial, in: shape)
            .overlay { WipeEdge(edgeOnly: true).stroke(Color(rgba: 0xFAFCFF99), lineWidth: 2) }
            .frame(width: width, height: height)
    }
}

/// The sheet: square on the left, its right side one big elliptical curve (CSS `border-radius: 0 48% 48% 0`).
private struct WipeEdge: Shape {
    var edgeOnly = false

    func path(in rect: CGRect) -> Path {
        let rx = rect.width * 0.48, ry = rect.height * 0.48
        let k = 0.5523
        var path = Path()
        if edgeOnly {
            path.move(to: CGPoint(x: rect.maxX - rx, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - rx, y: rect.minY))
        }
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                      control1: CGPoint(x: rect.maxX - rx + rx * k, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + ry - ry * k))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry))
        path.addCurve(to: CGPoint(x: rect.maxX - rx, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.maxY - ry + ry * k),
                      control2: CGPoint(x: rect.maxX - rx + rx * k, y: rect.maxY))
        if !edgeOnly {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
