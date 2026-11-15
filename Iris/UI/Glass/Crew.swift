import SwiftUI

/// The four rounded characters on the welcome screen: Skye with ears, Pip with glasses, Nova in a lab
/// coat and Echo with headphones. Two peek from behind and two sit in front, each popping in from its
/// own side, then bobbing, blinking and glancing on its own rhythm.
struct Crew: View {
    let stage: Stage

    private struct Friend {
        let art: VectorArt
        /// Position in `IRIS_ASSETS.heroCrew`, which staggers every rhythm.
        let index: Int
        let frame: CGRect
        let lean: Double
        let enter: CGPoint
    }

    /// Back to front, as the design stacks them.
    private static let friends = [
        Friend(art: IrisArtwork.skye, index: 0, frame: CGRect(x: 20, y: 280, width: 210, height: 262.5),
               lean: -8, enter: CGPoint(x: -65, y: 30)),
        Friend(art: IrisArtwork.echo, index: 3, frame: CGRect(x: 154, y: 328, width: 190, height: 237.5),
               lean: 10, enter: CGPoint(x: 70, y: -35)),
        Friend(art: IrisArtwork.pip, index: 1, frame: CGRect(x: 20, y: 448, width: 207, height: 258.75),
               lean: -6, enter: CGPoint(x: -55, y: 85)),
        Friend(art: IrisArtwork.nova, index: 2, frame: CGRect(x: 148, y: 431, width: 210, height: 262.5),
               lean: 6, enter: CGPoint(x: 60, y: 100)),
    ]

    @State private var since = Date()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.friends, id: \.index) { friend in
                character(friend)
                    .placed(friend.frame, on: stage)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Four Iris characters: Skye with ears, Pip with glasses, Nova in a lab coat, and Echo with headphones and a scarf")
        .accessibilityAddTraits(.isImage)
    }

    private func character(_ friend: Friend) -> some View {
        let i = Double(friend.index)
        return VectorArtView(art: friend.art, animate: { name in
            switch name {
            // friend-blink: 7.8 s, from 2 s + 1.1 s apart.
            case "mini-eyes":
                [Motion(7.8, delay: i * 1.1 + 2, repeats: true, [
                    (0, .rest), (0.63, .rest), (0.65, Pose(scaleX: 1, scaleY: 0.08)), (0.67, .rest), (1, .rest),
                ])]
            // friend-glance: 10 s, offset by 1.8 s each.
            case "mini-gaze":
                [Motion(10, delay: -i * 1.8, curve: .easeInOut, repeats: true, [
                    (0, .rest), (0.15, .rest), (0.3, Pose(x: -3, y: -2)), (0.4, Pose(x: -3, y: -2)),
                    (0.6, Pose(x: 2, y: 1)), (0.7, Pose(x: 2, y: 1)), (0.9, .rest), (1, .rest),
                ])]
            default:
                []
            }
        }, since: since)
        // huddle-bob, about the feet.
        .motion(Motion(3.8 + i * 0.4, delay: -i * 0.7, curve: .easeInOut, repeats: true, alternate: true,
                       from: Pose(rotation: friend.lean), to: Pose(y: -7, rotation: friend.lean * 0.55)),
                unit: stage.unit, anchor: UnitPoint(x: 0.5, y: 0.75))
        .shadow(color: Color(rgba: 0x061B3733), radius: 4 * stage.unit, y: 8 * stage.unit)
        // huddle-hello: from its own side, with a little overshoot.
        .motion(Motion(0.95, delay: 0.45 + i * 0.13, curve: Bezier(0.2, 0.8, 0.25, 1.1), [
            (0, Pose(x: friend.enter.x, y: friend.enter.y, scale: 0.7, opacity: 0)),
            (0.75, Pose(y: -5, scale: 1.035)),
            (1, .rest),
        ]), unit: stage.unit)
        // Reduced motion keeps the lean.
        .modifier(ReducedLean(lean: friend.lean))
    }
}

/// `huddle-bob` stops under reduced motion, but each character keeps its resting tilt.
private struct ReducedLean: ViewModifier {
    let lean: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(reduceMotion ? lean : 0), anchor: UnitPoint(x: 0.5, y: 0.75))
    }
}
