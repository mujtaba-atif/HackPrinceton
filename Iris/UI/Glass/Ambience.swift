import SwiftUI

// The design's surfaces and decoration: backgrounds, film grain, sprinkles, floating glass and confetti.
// Decoration never takes touches and is hidden from VoiceOver.

/// A CSS `linear-gradient(<angle>deg, …)` across a rect, with the same gradient line CSS uses.
struct CSSLinearGradient: View {
    var angle: Double
    var stops: [Gradient.Stop]

    var body: some View {
        GeometryReader { geo in
            let (start, end) = Self.points(angle: angle, size: geo.size)
            LinearGradient(stops: stops, startPoint: start, endPoint: end)
        }
    }

    /// The gradient line's ends, as unit points of a rect of `size`.
    static func points(angle: Double, size: CGSize) -> (UnitPoint, UnitPoint) {
        let radians = angle * .pi / 180
        let dx = sin(radians), dy = -cos(radians)
        let length = abs(size.width * dx) + abs(size.height * dy)
        let half = CGPoint(x: dx * length / 2, y: dy * length / 2)
        guard size.width > 0, size.height > 0 else { return (.top, .bottom) }
        return (UnitPoint(x: 0.5 - half.x / size.width, y: 0.5 - half.y / size.height),
                UnitPoint(x: 0.5 + half.x / size.width, y: 0.5 + half.y / size.height))
    }
}

/// A CSS `radial-gradient(ellipse at x% y%, color, transparent stop%)`, sized to the farthest corner.
struct CSSRadialGlow: View {
    var center: UnitPoint
    var color: Color
    var stop: Double

    var body: some View {
        Canvas { context, size in
            let cx = center.x * size.width, cy = center.y * size.height
            let rx = max(cx, size.width - cx) * 2.squareRoot()
            let ry = max(cy, size.height - cy) * 2.squareRoot()
            guard rx > 0, ry > 0 else { return }
            context.translateBy(x: cx, y: cy)
            context.scaleBy(x: rx, y: ry)
            context.fill(
                Path(CGRect(x: -2, y: -2, width: 4, height: 4)),
                with: .radialGradient(Gradient(stops: [.init(color: color, location: 0),
                                                       .init(color: color.opacity(0), location: stop)]),
                                      center: .zero, startRadius: 0, endRadius: 1)
            )
        }
    }
}

/// Loading and welcome: deep navy with a blue glow at the top right.
struct HomeBackdrop: View {
    var body: some View {
        ZStack {
            CSSLinearGradient(angle: 135, stops: [.init(color: IrisPalette.deep, location: 0),
                                                  .init(color: IrisPalette.navy, location: 0.7)])
            CSSRadialGlow(center: UnitPoint(x: 0.9, y: 0.05), color: Color(rgba: 0x297FDB66), stop: 0.52)
            FilmGrain()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The options screen: open blue water with light from the top right.
struct OptionsBackdrop: View {
    var body: some View {
        ZStack {
            CSSLinearGradient(angle: 145, stops: [.init(color: IrisPalette.blue, location: 0),
                                                  .init(color: IrisPalette.water, location: 0.6),
                                                  .init(color: IrisPalette.navy, location: 1)])
            CSSRadialGlow(center: UnitPoint(x: 1, y: 0), color: Color(rgba: 0xB5DEFA88), stop: 0.62)
            FilmGrain()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The faint fractal noise laid over every screen (4.5% white).
struct FilmGrain: View {
    private static let tile: CGImage? = {
        let side = 160
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        var generator = SystemRandomNumberGenerator()
        for i in 0..<(side * side) {
            let alpha = UInt8.random(in: 0...255, using: &generator)
            // Premultiplied white.
            pixels[i * 4] = alpha
            pixels[i * 4 + 1] = alpha
            pixels[i * 4 + 2] = alpha
            pixels[i * 4 + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }()

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 1)
                .resizable(resizingMode: .tile)
                .opacity(0.045)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}

/// Drifting confetti-like specks: little capsules, dots, arcs and four-point stars. `quiet` is the
/// sparse version along the edges of the camera screens. Hidden under reduced motion.
struct Sprinkles: View {
    var count = 20
    var quiet = false
    var unit: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Speck {
        var x, y: Double
        var rotation: Double
        var delay: Double
        var duration: Double
        var drift: Double
        var color: Color
        var kind: Int
    }

    private var specks: [Speck] {
        (0..<count).map { i in
            Speck(
                x: quiet ? (i % 2 == 1 ? 0.94 : 0.04) : Double((i * 47 + 13) % 96) / 100,
                y: quiet ? (18 + Double(i) * 10) / 100 : Double((i * 71 + 29) % 94) / 100,
                rotation: Double(i * 41),
                delay: -Double(i) * 0.63,
                duration: 6 + Double(i % 5),
                drift: i % 2 == 1 ? -22 : 22,
                color: IrisPalette.confetti[i % 4],
                kind: i % 4
            )
        }
    }

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    for speck in specks { draw(speck, at: t, in: &context, size: size) }
                }
            }
            .opacity(quiet ? 0.4 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
        }
    }

    private func draw(_ speck: Speck, at t: Double, in context: inout GraphicsContext, size: CGSize) {
        // sprinkle-drift: alternate, ease-in-out; the transform runs 0 → 100%, opacity .25 → .75 (45%) → .35.
        let local = (t - speck.delay) / speck.duration
        var progress = local - local.rounded(.down)
        if Int(local.rounded(.down)) % 2 != 0 { progress = 1 - progress }
        let moved = Bezier.easeInOut(progress)
        let opacity = progress < 0.45
            ? 0.25 + 0.5 * Bezier.easeInOut(progress / 0.45)
            : 0.75 - 0.4 * Bezier.easeInOut((progress - 0.45) / 0.55)
        let dx = speck.drift * moved * unit
        let dy = (-10 + 33 * moved) * unit
        let angle = Angle.degrees(speck.rotation + 100 * moved)

        var c = context
        c.opacity = opacity
        c.translateBy(x: speck.x * size.width + dx, y: speck.y * size.height + dy)
        c.rotate(by: angle)
        let shading = GraphicsContext.Shading.color(speck.color)
        let small = quiet
        switch speck.kind {
        case 1:
            let w = (small ? 3 : 6) * unit, h = (small ? 8 : 6) * unit
            c.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h)), with: shading)
        case 2:
            let side = (small ? 8 : 12) * unit
            var arc = Path()
            arc.addArc(center: CGPoint(x: side / 2, y: side / 2), radius: side / 2 - unit,
                       startAngle: .degrees(-135), endAngle: .degrees(45), clockwise: false)
            c.stroke(arc, with: shading, lineWidth: 2 * unit)
        case 3:
            let side = (small ? 9 : 12) * unit
            var star = Path()
            let points: [(Double, Double)] = [(0.5, 0), (0.62, 0.38), (1, 0.5), (0.62, 0.62),
                                              (0.5, 1), (0.38, 0.62), (0, 0.5), (0.38, 0.38)]
            star.addLines(points.map { CGPoint(x: $0.0 * side, y: $0.1 * side) })
            star.closeSubpath()
            c.fill(star, with: shading)
        default:
            let w = (small ? 3 : 5) * unit, h = (small ? 8 : 13) * unit
            c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: min(3 * unit, w / 2)), with: shading)
        }
    }
}

/// A floating pane of glass with a light sweeping across it (and a ✦ on the larger one).
struct GlassFloat: View {
    var cornerRadius: CGFloat = 22
    var sparkle: (size: CGFloat, x: CGFloat, y: CGFloat)?
    var unit: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius * unit, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.25))
            .overlay {
                CSSLinearGradient(angle: 140, stops: [.init(color: Color(rgba: 0xFAFCFF22), location: 0),
                                                      .init(color: Color(rgba: 0xB5DEFA06), location: 0.48),
                                                      .init(color: Color(rgba: 0x72C7F52A), location: 1)])
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius * unit, style: .continuous))
            }
            .overlay { GlassSheen().clipShape(RoundedRectangle(cornerRadius: cornerRadius * unit, style: .continuous)) }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius * unit, style: .continuous)
                    .strokeBorder(Color(rgba: 0xFAFCFF70), lineWidth: max(1, unit))
            }
            .overlay(alignment: .topLeading) {
                if let sparkle {
                    Text("✦")
                        .font(.system(size: sparkle.size * unit))
                        .foregroundStyle(IrisPalette.glass)
                        .offset(x: sparkle.x * unit, y: sparkle.y * unit)
                }
            }
            .shadow(color: Color(rgba: 0x061B3724), radius: 15 * unit, y: 14 * unit)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The band of light that crosses a glass surface every six seconds (`glass-sheen`).
struct GlassSheen: View {
    var body: some View {
        GeometryReader { geo in
            CSSLinearGradient(angle: 120, stops: [.init(color: .clear, location: 0.38),
                                                  .init(color: Color(rgba: 0xFAFCFF55), location: 0.48),
                                                  .init(color: .clear, location: 0.57)])
                .frame(width: geo.size.width * 2, height: geo.size.height * 2)
                .motion(Motion(6, curve: .easeInOut, repeats: true, [
                    (0, Pose(x: -0.55 * geo.size.width * 2)), (0.2, Pose(x: -0.55 * geo.size.width * 2)),
                    (0.65, Pose(x: 0.55 * geo.size.width * 2)), (1, Pose(x: 0.55 * geo.size.width * 2)),
                ]))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

/// Success confetti: 32 pieces burst up from low in the middle of the screen and fall away (1.8 s).
/// Each change of `trigger` fires one burst. Nothing under reduced motion.
struct Confetti: View {
    var trigger: Int
    var unit: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstAt: Date?

    private static let life = 2.3
    private static let curve = Bezier(0.15, 0.5, 0.4, 1)

    var body: some View {
        Group {
            if let burstAt, !reduceMotion {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(burstAt)
                    Canvas { context, size in draw(at: t, in: &context, size: size) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .onChange(of: trigger) {
            let fired = Date()
            burstAt = fired
            Task {
                try? await Task.sleep(for: .seconds(Self.life))
                if burstAt == fired { burstAt = nil }
            }
        }
    }

    private func draw(at t: Double, in context: inout GraphicsContext, size: CGSize) {
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.75)
        for i in 0..<32 {
            let local = t - Double(i % 5) * 0.045
            guard local > 0 else { continue }
            let p = min(1, local / 1.8)
            let eased = Self.curve(p)
            let dx = cos(Double(i) * 2.4) * (85 + Double(i % 6) * 19)
            let dy = -130 - sin(Double(i) * 1.7) * 140
            let opacity = p < 0.12 ? p / 0.12 : p < 0.72 ? 1 - 0.15 * (p - 0.12) / 0.6 : 0.85 * (1 - (p - 0.72) / 0.28)
            let scale = 0.2 + 0.4 * eased

            var c = context
            c.opacity = opacity
            c.translateBy(x: origin.x + dx * eased * unit, y: origin.y + dy * eased * unit)
            c.rotate(by: .degrees(Double(i * 57) * eased))
            c.scaleBy(x: scale, y: scale)
            let color = GraphicsContext.Shading.color(IrisPalette.confetti[i % 4])
            if i % 3 == 2 {
                c.fill(Path(ellipseIn: CGRect(x: -4.5 * unit, y: -4.5 * unit, width: 9 * unit, height: 9 * unit)), with: color)
            } else {
                c.fill(Path(roundedRect: CGRect(x: -3.5 * unit, y: -6.5 * unit, width: 7 * unit, height: 13 * unit),
                            cornerRadius: 3 * unit), with: color)
            }
        }
    }
}
