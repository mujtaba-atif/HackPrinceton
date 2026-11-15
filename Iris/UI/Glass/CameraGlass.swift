import SwiftUI

/// The way the hand has to move, as the guidance is steering it. `nil` is "lined up on this axis".
enum RippleDirection {
    case left, right, forward, back
}

/// The on-screen half of the guidance cue, written by `DistanceBeepController` and read only by
/// `CameraGlass`.
///
/// `@Observable` rather than `@Published` on the controller: it moves ~10 times a second while the camera
/// screen is up, and a published change would rebuild the whole of `LocateScreen` at that rate. This way
/// only the waves re-evaluate.
@Observable
final class GuidanceCue {
    var direction: RippleDirection?
    /// 0 as far off as the axis measures, 1 lined up. Brightness only.
    var intensity: Double = 0
}

/// What the conversation is doing, as the waves show it.
enum WaterMood {
    /// Nothing to say: before the handoff, and after the conversation has gone.
    case still
    /// Reading the label off the object.
    case drawingIn
    case thinking
    case listening
    case speaking
}

/// The three translucent glass waves over the camera: one from the top, one down each side, in a
/// dark-blue-to-ice gradient. They sweep in when the camera opens and then sway gently.
///
/// Locate's guidance rides on them. Forward and back are the top wave, which surges down the screen
/// (reach out) or draws back up (bring it back); left and right are the side waves, which surge in from
/// the side the hand has to move toward. Being closer to lined up makes the moving wave brighter. After
/// the handoff the waves follow the conversation instead: they close in a little while the label is read,
/// breathe slowly while Iris listens and swell in time while Iris speaks.
struct CameraGlass: View {
    enum Mode { case locate, explore }

    var mode: Mode = .locate
    var cue: GuidanceCue?
    var mood: WaterMood = .still

    @Environment(\.irisUnit) private var unit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var since = Date()
    /// The waves have swept in; with nothing to show the frame clock can stop (each wave's own sway
    /// keeps running on its own).
    @State private var settled = false
    /// When the label read turned into the conversation: the waves flash and surge once.
    @State private var splashAt: Date?

    private var idle: Bool { settled && cue?.direction == nil && mood == .still }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: reduceMotion || idle)) { timeline in
                let t = timeline.date.timeIntervalSince(since)
                let push = surge(at: t)
                ZStack(alignment: .topLeading) {
                    // Top: 133% wide, 260 tall, from 25 above the top edge.
                    topTide(t: t)
                        .frame(width: size.width * 4 / 3, height: 260 * unit)
                        .offset(x: -size.width / 6, y: -25 * unit + push.top)
                        .brightness(push.topGlow - 1)
                    // Sides: 82 wide, 650 tall, from 150 down, 20 past each edge.
                    sideTide(t: t, mirrored: false)
                        .frame(width: 82 * unit, height: 650 * unit)
                        .offset(x: -20 * unit + push.left, y: 150 * unit)
                        .brightness(push.leftGlow - 1)
                    sideTide(t: t, mirrored: true)
                        .frame(width: 82 * unit, height: 650 * unit)
                        .scaleEffect(x: -1, y: 1)
                        .offset(x: size.width - 62 * unit - push.right, y: 150 * unit)
                        .opacity(0.8)
                        .brightness(push.rightGlow - 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .onAppear { since = .now }
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            settled = true
        }
        .onChange(of: mood) { old, new in
            if old == .drawingIn, new != .still, new != .drawingIn { splashAt = .now }
        }
    }

    // MARK: Entrances and sway

    private var enterTop: Motion {
        Motion(mode == .explore ? 1.55 : 1.35, curve: Bezier(0.15, 0.75, 0.25, 1), [
            (0, Pose(y: -310, opacity: 0)), (0.6, Pose(y: 18)), (1, .rest),
        ])
    }

    private func enterSide(right: Bool) -> Motion {
        let duration = mode == .explore ? (right ? 1.7 : 1.2) : 1.55
        let hold = right ? 0.2 : 0.12, overshoot = right ? 0.78 : 0.75
        let from = right ? 120.0 : -120.0
        return Motion(duration, curve: Bezier(0.2, 0.75, 0.25, 1), [
            (0, Pose(x: from, opacity: 0)), (hold, Pose(x: from, opacity: 0)),
            (overshoot, Pose(x: right ? -10 : 10)), (1, .rest),
        ])
    }

    private func pose(_ motion: Motion, _ t: Double) -> Pose {
        reduceMotion ? motion.settled : motion.pose(at: t)
    }

    private func topTide(t: Double) -> some View {
        let enter = pose(enterTop, t)
        return VectorArtView(art: IrisArtwork.waveTop, animate: { name in
            switch name {
            case "wave-deep": [Motion(8.4, curve: .easeInOut, repeats: true, alternate: true,
                                      from: Pose(x: -14, y: -5), to: Pose(x: 20, y: 7))]
            case "wave-mid": [Motion(6.8, curve: .easeInOut, repeats: true, alternate: true,
                                     from: Pose(x: 22, y: 3), to: Pose(x: -22, y: -5))]
            case "wave-light": [Motion(9.6, curve: .easeInOut, repeats: true, alternate: true,
                                       from: Pose(x: -26, y: -6), to: Pose(x: 26, y: 8))]
            default: []
            }
        }, since: since)
        .shadow(color: Color(rgba: 0x72C7F51A), radius: 3.5 * unit, y: 2 * unit)
        .pose(enter, unit: unit)
    }

    private func sideTide(t: Double, mirrored: Bool) -> some View {
        let enter = pose(enterSide(right: mirrored), t)
        return VectorArtView(art: IrisArtwork.waveSide, animate: { name in
            switch name {
            case "side-ribbon": [Motion(9, curve: .easeInOut, repeats: true, alternate: true,
                                        from: mirrored ? Pose(x: 9, y: 14) : Pose(x: -7, y: -14),
                                        to: mirrored ? Pose(x: -7, y: -14) : Pose(x: 9, y: 14))]
            case "side-glint": [Motion(7, curve: .easeInOut, repeats: true, alternate: true,
                                       from: Pose(x: 3, y: 15, opacity: 0.3), to: Pose(x: -3, y: -15, opacity: 0.8))]
            default: []
            }
        }, since: since)
        .shadow(color: Color(rgba: 0x72C7F51A), radius: 3.5 * unit, y: 2 * unit)
        // Mirrored by the caller, so the entrance's x is flipped back here.
        .pose(mirrored ? Pose(x: -enter.x, opacity: enter.opacity) : enter, unit: unit)
    }

    // MARK: Guidance and conversation

    /// How far each wave is pushed in (points) and how bright it is, from the cue and the mood.
    private struct Push {
        var top: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0
        var topGlow = 1.0, leftGlow = 1.0, rightGlow = 1.0
    }

    /// One surge every 1.7 s, the same cadence the on-screen guidance has always used; closeness is
    /// brightness, never speed, so the rhythm never jumps.
    static let surgePeriod = 1.7

    /// 0…1…0 over one period: a quick swell in, a slower ebb.
    static func swell(_ phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        return p < 0.35 ? Bezier.easeOut(p / 0.35) : 1 - Bezier.easeInOut((p - 0.35) / 0.65)
    }

    /// How far a guided wave travels in at the top of a surge, in design points.
    static let surgeReach: CGFloat = 70

    private func surge(at t: Double) -> Push {
        var push = Push()
        if let cue, let direction = cue.direction {
            let wave = reduceMotion ? 0.5 : Self.swell(t / Self.surgePeriod)
            let reach = Self.surgeReach * unit * wave
            let glow = 1 + (0.25 + 0.35 * cue.intensity) * wave
            switch direction {
            case .forward:
                push.top = reach
                push.topGlow = glow
            case .back:
                push.top = -reach * 0.8
                push.topGlow = glow
            case .left:
                push.left = reach * 0.6
                push.leftGlow = glow
            case .right:
                push.right = reach * 0.6
                push.rightGlow = glow
            }
            return push
        }
        let depth: Double
        switch mood {
        case .still: return push
        case .drawingIn: depth = 26
        case .thinking: depth = 14 + 6 * (reduceMotion ? 0 : sin(t * 2 * .pi / 2.4))
        case .listening: depth = 12 + 8 * (reduceMotion ? 0 : sin(t * 2 * .pi / 3.2))
        case .speaking: depth = 16 + 14 * (reduceMotion ? 0.5 : Self.swell(t / 0.62))
        }
        // The splash: one bright surge as the reading becomes a conversation (0.95 s).
        var splash = 0.0
        if let splashAt, !reduceMotion {
            let age = Date().timeIntervalSince(splashAt) / 0.95
            if age < 1 { splash = sin(age * .pi) }
        }
        let reach = (depth + 30 * splash) * unit
        push.top = reach
        push.left = reach * 0.5
        push.right = reach * 0.5
        let glow = (mood == .speaking ? 1.15 : 1.05) + 0.35 * splash
        push.topGlow = glow
        push.leftGlow = glow
        push.rightGlow = glow
        return push
    }
}
