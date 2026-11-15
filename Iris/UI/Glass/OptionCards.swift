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

/// The Locate card (`find.svg`): navy glass with a pair of curious eyes under a floating glass pane.
/// The pupils wander up, left, down and right; the eyes blink twice every 8.6 s.
struct LocateCard: View {
    @State private var since = Date()
    private let tilt = DeviceTilt.shared

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 305
            ZStack(alignment: .topLeading) {
                VectorArtView(art: IrisArtwork.locateCard, animate: { name in
                    switch name {
                    case "findEyeAssembly":
                        [Motion(8.6, delay: 1.2, repeats: true, [
                            (0, .rest), (0.37, .rest), (0.385, Pose(scaleX: 1, scaleY: 0.06)), (0.40, .rest),
                            (0.83, .rest), (0.845, Pose(scaleX: 1, scaleY: 0.06)), (0.86, .rest), (1, .rest),
                        ])]
                    case "findPupils":
                        [Motion(12.4, curve: .easeInOut, repeats: true, [
                            (0, .rest), (0.08, .rest),
                            (0.16, Pose(y: -12)), (0.24, Pose(y: -12)),
                            (0.32, Pose(x: -14, y: -2)), (0.40, Pose(x: -14, y: -2)),
                            (0.48, Pose(x: -2, y: 12)), (0.56, Pose(x: -2, y: 12)),
                            (0.64, Pose(x: 14, y: 1)), (0.72, Pose(x: 14, y: 1)),
                            (0.80, Pose(x: 8, y: -10)), (0.88, Pose(x: 8, y: -10)),
                            (0.96, .rest), (1, .rest),
                        ])]
                    default:
                        []
                    }
                }, since: since, respond: { name in
                    // The pupils also look where the phone tilts; a jolt blinks and widens the eyes.
                    switch name {
                    case "findEyeAssembly": EyeResponse(blinks: tilt.blinks)
                    case "findEyes": EyeResponse(scale: tilt.surprised ? 1.07 : 1)
                    case "findPupils": EyeResponse(offset: CGPoint(x: tilt.look.x * 10, y: tilt.look.y * 7),
                                                   scale: tilt.surprised ? 0.8 : 1)
                    default: nil
                    }
                })
                .clipShape(RoundedRectangle(cornerRadius: 23 * k, style: .continuous))

                CardText(text: "LOCATE", font: IrisFont.nunitoSans(37 * k, .extraBold), size: 37, tracking: 1,
                         color: IrisPalette.white, x: 56, baseline: 89 + 37 * 0.329, anchor: .middle, k: k)
                    .rotationEffect(.degrees(-90), anchor: UnitPoint(x: 56 / 305, y: 89 / 177))
                CardText(text: "YOUR WORLD, WITHIN REACH", font: IrisFont.nunito(10 * k, .bold), size: 10,
                         tracking: 1.2, color: IrisPalette.glass, x: 107, baseline: 163, k: k)

                EyeGlass(k: k)
                    .frame(width: 188 * k, height: 111 * k)
                    .offset(x: 95 * k, y: 30 * k)
            }
        }
        .aspectRatio(305 / 177, contentMode: .fit)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }
}

/// The pane of glass drifting over the Locate card's eyes (`eye-glass`).
private struct EyeGlass: View {
    var k: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 23 * k, style: .continuous)
        shape
            .fill(.clear)
            .overlay {
                CSSLinearGradient(angle: 135, stops: [.init(color: Color(rgba: 0xFAFCFF30), location: 0),
                                                      .init(color: Color(rgba: 0xB5DEFA04), location: 0.43),
                                                      .init(color: Color(rgba: 0x72C7F51A), location: 1)])
            }
            .overlay { GlassSheen() }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color(rgba: 0xFAFCFF99), lineWidth: max(1, k)) }
            .shadow(color: Color(rgba: 0x061B3730), radius: 12 * k, y: 12 * k)
            .rotationEffect(.degrees(-7))
            .motion(Motion(5.4, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -6, y: -4, rotation: -1), to: Pose(x: 8, y: 5, rotation: 10)), unit: k)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The Explore card (`analyze.svg`): an ice-white card with a rectangular glass lens sweeping across it.
struct ExploreCard: View {
    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 305
            ZStack(alignment: .topLeading) {
                VectorArtView(art: IrisArtwork.exploreCard)
                    .clipShape(RoundedRectangle(cornerRadius: 23 * k, style: .continuous))
                CardText(text: "A CLOSER LOOK", font: IrisFont.nunito(10 * k, .bold), size: 10, tracking: 1.8,
                         color: IrisPalette.blue, x: 21, baseline: 53, k: k)
                CardText(text: "EXPLORE", font: IrisFont.nunitoSans(43 * k, .black), size: 43, tracking: -1.5,
                         color: IrisPalette.navy, x: 152.5, baseline: 110, anchor: .middle, k: k)
                CardText(text: "READ. ASK. UNDERSTAND.", font: IrisFont.nunito(10 * k, .bold), size: 10,
                         tracking: 1.2, color: IrisPalette.navy, x: 22, baseline: 162, k: k)
                ExploreOptic(k: k)
                    .frame(width: 105 * k, height: 111 * k)
                    .offset(x: 154 * k, y: 31 * k)
            }
        }
        .aspectRatio(305 / 177, contentMode: .fit)
    }
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
        .motion(Motion(5, curve: .easeInOut, repeats: true, alternate: true,
                       from: Pose(x: -32, y: -7, rotation: -9), to: Pose(x: 12, y: 8, rotation: 12)), unit: k)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
