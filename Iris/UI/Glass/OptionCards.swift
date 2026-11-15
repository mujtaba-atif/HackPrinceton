import SwiftUI

/// Places SVG-style text inside a card drawn at `k` screen points per card unit. `x`/`baseline` are
/// where the SVG's `<text>` sits; `anchor` is its `text-anchor`.
private struct CardText: View {
    enum Anchor { case start, middle }

    var text: String
    var font: Font
    var size: CGFloat
    var tracking: CGFloat = 0
    var color: Color
    var x: CGFloat
    var baseline: CGFloat
    var anchor: Anchor = .start
    var k: CGFloat

    /// Nunito's ascent and descent per point of size; the line box is their sum, the baseline sits at the
    /// ascent.
    private static let ascent: CGFloat = 1.011, descent: CGFloat = 0.353

    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking * k)
            .foregroundStyle(color)
            .fixedSize()
            .frame(width: 0, height: 0, alignment: anchor == .start ? .leading : .center)
            .position(x: x * k, y: (baseline - size * (Self.ascent - (Self.ascent + Self.descent) / 2)) * k)
    }
}

/// The split is 448 points high at the left and 352 at the right on the 800-point stage.
/// Clipping and hit testing use the same path, so overlapping rectangular frames never steal a tap.
struct DiscoverySplit: Shape {
    var explore: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let left = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.56)
        let right = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.44)
        p.move(to: left)
        p.addLine(to: right)
        p.addLine(to: CGPoint(x: rect.maxX, y: explore ? rect.maxY : rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: explore ? rect.maxY : rect.minY))
        p.closeSubpath()
        return p
    }
}

struct DiscoveryPanel: View {
    var explore: Bool
    let stage: Stage
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                VectorArtView(art: explore ? IrisArtwork.explorePanel : IrisArtwork.locatePanel)
                    .frame(width: stage.size.width, height: stage.size.height * 0.56)
                    .offset(y: explore ? stage.size.height * 0.44 : 0)
                Group {
                    if explore { ExploreCard() } else { LocateCard() }
                }
                .motion(drift, unit: stage.unit)
                .rotationEffect(.degrees(reduceMotion ? (explore ? 2 : -2) : 0))
                .placed(x: 27.5, y: explore ? 511.5 : 111.5, width: 305, height: 177, on: stage)
            }
            .frame(width: stage.size.width, height: stage.size.height)
            .contentShape(DiscoverySplit(explore: explore))
            .clipShape(DiscoverySplit(explore: explore))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(explore ? "Explore an object" : "Locate an object")
        .accessibilityHint(explore ? "Or say explore" : "Or say locate")
    }

    private var drift: Motion {
        if explore {
            return Motion(7.2, delay: -0.9, curve: .easeInOut, repeats: true, [
                (0, Pose(rotation: 2)), (0.25, Pose(x: 3, y: 6, rotation: 2.8)),
                (0.5, Pose(y: 2, rotation: 2)), (0.75, Pose(x: -3, y: -7, rotation: 1.2)), (1, Pose(rotation: 2))
            ])
        }
        return Motion(6.4, curve: .easeInOut, repeats: true, [
            (0, Pose(rotation: -2)), (0.25, Pose(x: -3, y: -7, rotation: -2.8)),
            (0.5, Pose(y: -2, rotation: -2)), (0.75, Pose(x: 3, y: 6, rotation: -1.2)), (1, Pose(rotation: -2))
        ])
    }
}

/// Shared revision 18 vectors, with native text at the exact SVG baselines.
struct LocateCard: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 305
            ZStack(alignment: .topLeading) {
                VectorArtView(art: IrisArtwork.locateCard)
                CardText(text: "LOCATE", font: IrisFont.nunitoSans(37 * k, .extraBold), size: 37, tracking: 1,
                         color: IrisPalette.white, x: 64, baseline: 89 + 37 * 0.329, anchor: .middle, k: k)
                    .rotationEffect(.degrees(-90), anchor: UnitPoint(x: 64 / 305, y: 89 / 177))
                CardText(text: "YOUR WORLD, WITHIN REACH", font: IrisFont.nunito(10 * k, .bold), size: 10,
                         tracking: 1.2, color: IrisPalette.glass, x: 95, baseline: 163, k: k)
                TreasureMap()
                    .frame(width: 213.2 * k, height: 152.52 * k)
                    .offset(x: 91 * k, y: -8 * k)
                    .modifier(DiscoveryMotionResponse(distance: 14, rotation: 2.2, unit: k))
            }
        }
        .aspectRatio(305 / 177, contentMode: .fit)
    }
}

struct ExploreCard: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 305
            ZStack(alignment: .topLeading) {
                VectorArtView(art: IrisArtwork.exploreCard)
                CardText(text: "A CLOSER LOOK", font: IrisFont.nunito(10 * k, .bold), size: 10, tracking: 1.8,
                         color: IrisPalette.blue, x: 27, baseline: 53, k: k)
                CardText(text: "EXPLORE", font: IrisFont.nunitoSans(43 * k, .black), size: 43, tracking: -1.5,
                         color: IrisPalette.navy, x: 152.5, baseline: 110, anchor: .middle, k: k)
                CardText(text: "READ. ASK. UNDERSTAND.", font: IrisFont.nunito(10 * k, .bold), size: 10,
                         tracking: 1.2, color: IrisPalette.navy, x: 42, baseline: 162, k: k)
                ExploreOptic(k: k)
                    .frame(width: 105 * k, height: 111 * k)
                    .offset(x: 154 * k, y: 31 * k)
                    .modifier(DiscoveryMotionResponse(distance: 22, rotation: 3.5, unit: k))
            }
        }
        .aspectRatio(305 / 177, contentMode: .fit)
    }
}

struct GlassSkew: ViewModifier {
    var degrees: Double
    func body(content: Content) -> some View {
        content.transformEffect(CGAffineTransform(a: 1, b: 0, c: tan(degrees * .pi / 180), d: 1, tx: 0, ty: 0))
    }
}

private struct DiscoveryMotionResponse: ViewModifier {
    var distance: CGFloat
    var rotation: Double
    var unit: CGFloat
    private let tilt = DeviceTilt.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : tilt.shake * distance * unit)
            .rotationEffect(.degrees(reduceMotion ? 0 : tilt.shake * rotation))
            .onAppear { tilt.start() }
            .onDisappear { tilt.stop() }
    }
}

private struct TreasureMap: View {
    @State private var since = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            VectorArtView(art: IrisArtwork.treasureMap, animate: motions, since: since,
                          hiddenGroups: reduceMotion ? ["mapCourier"] : [],
                          dashSpeeds: ["mapRoute": -44 / 6])
                .motion(Motion(6.2, curve: .easeInOut, repeats: true, [
                    (0, Pose(x: -12, y: 1, rotation: -4)), (0.5, Pose(x: 10, y: -7, rotation: 4)),
                    (1, Pose(x: -12, y: 1, rotation: -4))
                ]), unit: geo.size.width / 213.2, anchor: UnitPoint(x: 0.5, y: 0.7))
                .shadow(color: Color(rgba: 0x061B3740), radius: 7, y: 9)
        }
    }

    private func motions(_ name: String) -> [Motion] {
        switch name {
        case "mapCourier":
            return [Self.travel, Motion(6, curve: .linear, repeats: true, [
                (0, .rest), (0.77, .rest), (0.81, Pose(opacity: 0)), (1, Pose(opacity: 0))
            ])]
        case "mapX":
            return [Motion(6, curve: .easeInOut, repeats: true, [
                (0, .rest), (0.72, .rest), (0.8, Pose(rotation: -9, scale: 1.27)),
                (0.86, Pose(rotation: 5, scale: 0.96)), (0.93, Pose(rotation: -3, scale: 1.08)), (1, .rest)
            ])]
        case "mapDestinationHalo":
            return [Motion(6, curve: .easeOut, repeats: true, [
                (0, Pose(scale: 0.85, opacity: 0.1)), (0.7, Pose(scale: 0.85, opacity: 0.1)),
                (0.82, Pose(scale: 1.55, opacity: 0.3)), (0.96, Pose(scale: 1.9, opacity: 0)),
                (1, Pose(scale: 0.85, opacity: 0.1))
            ])]
        case "mapCompassNeedle":
            return [Motion(4, curve: .easeInOut, repeats: true, [
                (0, Pose(rotation: -16)), (0.35, Pose(rotation: 23)), (0.6, Pose(rotation: -5)), (1, Pose(rotation: -16))
            ])]
        case "mapSparkleA", "mapSparkleB":
            return [Motion(2.6, delay: name == "mapSparkleB" ? -1.3 : 0, curve: .easeInOut, repeats: true, [
                (0, Pose(rotation: -12, scale: 0.7, opacity: 0.35)),
                (0.5, Pose(rotation: 12, scale: 1.15)), (1, Pose(rotation: -12, scale: 0.7, opacity: 0.35))
            ])]
        default: return []
        }
    }

    // Coordinates from the reference's map-travel keyframes; the SVG itself remains shared and unmodified.
    private static let travel = Motion(6, curve: .linear, repeats: true, [
        (0, Pose(x: 0, y: 0)),
        (0.025, Pose(x: -1.296, y: -8.427)),
        (0.05, Pose(x: 1.15, y: -16.565)),
        (0.075, Pose(x: 6.843, y: -22.914)),
        (0.1, Pose(x: 14.287, y: -27.126)),
        (0.125, Pose(x: 22.534, y: -29.432)),
        (0.15, Pose(x: 31.083, y: -29.941)),
        (0.175, Pose(x: 39.519, y: -28.5)),
        (0.2, Pose(x: 47.709, y: -25.959)),
        (0.225, Pose(x: 56.181, y: -24.674)),
        (0.25, Pose(x: 64.716, y: -25.254)),
        (0.275, Pose(x: 72.459, y: -28.768)),
        (0.3, Pose(x: 77.208, y: -35.764)),
        (0.325, Pose(x: 78.062, y: -44.249)),
        (0.35, Pose(x: 75.994, y: -52.527)),
        (0.375, Pose(x: 71.24, y: -59.631)),
        (0.4, Pose(x: 65.125, y: -65.646)),
        (0.425, Pose(x: 60.074, y: -72.43)),
        (0.45, Pose(x: 63.621, y: -79.807)),
        (0.475, Pose(x: 70.765, y: -84.482)),
        (0.5, Pose(x: 79.064, y: -86.518)),
        (0.525, Pose(x: 87.622, y: -86.268)),
        (0.55, Pose(x: 95.987, y: -84.398)),
        (0.575, Pose(x: 104.024, y: -81.408)),
        (0.6, Pose(x: 111.705, y: -77.591)),
        (0.625, Pose(x: 119.014, y: -73.101)),
        (0.65, Pose(x: 126.324, y: -68.671)),
        (0.675, Pose(x: 134.759, y: -68.464)),
        (0.7, Pose(x: 142.195, y: -72.621)),
        (0.725, Pose(x: 148.05, y: -78.868)),
        (0.75, Pose(x: 152.667, y: -86.091)),
        (0.775, Pose(x: 156.288, y: -93.864)),
        (0.8, Pose(x: 159.0, y: -102.0)),
        (1, Pose(x: 159, y: -102))
    ])
}

/// The Explore card's sweeping lens (`explore-optic`), with its little handle.
private struct ExploreOptic: View {
    var k: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 25 * k, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape
                .fill(.clear)
                .overlay {
                    CSSLinearGradient(angle: 130, stops: [.init(color: Color(rgba: 0xFAFCFF99), location: 0),
                                                          .init(color: Color(rgba: 0xB5DEFA1A), location: 0.52),
                                                          .init(color: Color(rgba: 0x72C7F533), location: 1)])
                }
                .overlay {
                    CSSLinearGradient(angle: 120, stops: [.init(color: .clear, location: 0.38),
                                                          .init(color: Color(rgba: 0xFAFCFF55), location: 0.48),
                                                          .init(color: .clear, location: 0.57)])
                        .motion(Motion(5, curve: .easeInOut, repeats: true, alternate: true,
                                       from: Pose(opacity: 0.2), to: Pose(opacity: 0.8)))
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color(rgba: 0xFAFCFFB3), lineWidth: 2 * k) }
                .overlay {
                    shape.inset(by: 1.5 * k).stroke(.white.opacity(0.7), lineWidth: 1 * k).blur(radius: 1 * k)
                }
                .shadow(color: Color(rgba: 0x123A7340), radius: 12 * k, x: 6 * k, y: 14 * k)

            // The handle.
            RoundedRectangle(cornerRadius: 7 * k, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgba: 0xB5DEFA88), Color(rgba: 0xFAFCFF88), Color(rgba: 0x72C7F566)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 7 * k, style: .continuous)
                        .strokeBorder(Color(rgba: 0xFAFCFFAA), lineWidth: max(1, k))
                }
                .shadow(color: Color(rgba: 0x123A7322), radius: 4.5 * k, x: 3 * k, y: 5 * k)
                .frame(width: 19 * k, height: 51 * k)
                .rotationEffect(.degrees(-32))
                .offset(x: 82 * k, y: 97 * k)
        }
        .modifier(GlassSkew(degrees: -12))
        .motion(Motion(6.2, curve: .easeInOut, repeats: true, [
            (0, Pose(x: 19, y: -5, rotation: 12)), (0.5, Pose(x: -31, y: 7, rotation: -10)),
            (1, Pose(x: 19, y: -5, rotation: 12))
        ]), unit: k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
