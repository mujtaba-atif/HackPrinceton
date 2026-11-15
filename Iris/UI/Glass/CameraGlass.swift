import SwiftUI

/// The way the hand has to move, as the guidance is steering it. `nil` is "lined up on this axis".
enum RippleDirection {
    case left, right, forward, back
}

/// The on-screen half of the guidance cue, written by `DistanceBeepController` and read only by
/// the status panel.
///
/// `@Observable` rather than `@Published` on the controller: it moves ~10 times a second while the camera
/// screen is up, and a published change would rebuild the whole of `LocateScreen` at that rate. This way
/// only views reading the cue re-evaluate.
@Observable
final class GuidanceCue {
    var direction: RippleDirection?
    /// 0 as far off as the axis measures, 1 lined up. Brightness only.
    var intensity: Double = 0
}

/// What the conversation is doing.
enum WaterMood {
    /// Nothing to say: before the handoff, and after the conversation has gone.
    case still
    /// Reading the label off the object.
    case drawingIn
    case thinking
    case listening
    case speaking
}

/// Four narrow optical light strips from the shared revision 18 artwork. Their clocks persist
/// through recognition, success and conversation changes, matching the browser's flow-age behavior.
struct CameraGlass: View {
    enum Mode { case locate, explore }
    var mode: Mode = .locate
    var cue: GuidanceCue?
    var mood: WaterMood = .still
    @State private var since = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VectorArtView(art: IrisArtwork.edgeLights, animate: motion, since: since)
            .opacity(reduceMotion ? 0.8 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
    }

    private func motion(_ name: String) -> [Motion] {
        let duration: Double
        let returning: Bool
        switch name {
        case "edgeRayL1": duration = 5.8; returning = false
        case "edgeRayL2": duration = 7.2; returning = true
        case "edgeRayR1": duration = 6.4; returning = true
        case "edgeRayR2": duration = 8; returning = false
        default: return []
        }
        let first = returning ? Pose(x: 2, y: 25, opacity: 0.6) : Pose(x: -2, y: -22, opacity: 0.22)
        let second = returning ? Pose(x: -2, y: -26, opacity: 0.18) : Pose(x: 2, y: 28, opacity: 0.8)
        return [Motion(duration, curve: .easeInOut, repeats: true, [(0, first), (0.5, second), (1, first)])]
    }

    // Also used by the guidance tone's rhythm; keeping its timing independent of the visual rails.
    static let surgePeriod = 1.7
    static let surgeReach: CGFloat = 70
    static func swell(_ phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        return p < 0.35 ? Bezier.easeOut(p / 0.35) : 1 - Bezier.easeInOut((p - 0.35) / 0.65)
    }
}
