import CoreMotion
import SwiftUI

/// How the phone is held, for the little touches that answer it: eyes that look where the phone tilts,
/// a blink and wide eyes when it's jolted, and cards that drift downhill on the water.
///
/// One shared instance, started by the screens that use it. It publishes only when something visibly
/// moves, so a phone held still costs nothing.
@MainActor
@Observable
final class DeviceTilt {
    static let shared = DeviceTilt()

    /// Where the eyes look, -1…1 on each axis (+x right, +y down). Tilting ~15° looks all the way over.
    private(set) var look: CGPoint = .zero
    /// How the phone leans, about -1…1 (gravity x, and forward/back from a ~45° hold), for drifting.
    private(set) var lean: CGSize = .zero
    /// Bumped on a jolt or a quick flick; a blink trigger.
    private(set) var blinks = 0
    /// True for a moment after a jolt: wide eyes, small pupils.
    private(set) var surprised = false

    private let manager = CMMotionManager()
    private var users = 0
    private var lastBlink = Date.distantPast
    private var surprisedUntil = Date.distantPast

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated { self.update(motion) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
    }

    private func update(_ motion: CMDeviceMotion) {
        // Under Reduce Motion nothing follows the phone.
        guard !UIAccessibility.isReduceMotionEnabled else {
            if look != .zero { look = .zero }
            if lean != .zero { lean = .zero }
            return
        }
        let g = motion.gravity
        // Low-pass, so the eyes glide and the cards float rather than jitter.
        let lookTarget = CGPoint(x: Self.clamp(g.x / 0.25), y: Self.clamp((-g.z - 0.5) / 0.3))
        let next = CGPoint(x: look.x + (lookTarget.x - look.x) * 0.293, y: look.y + (lookTarget.y - look.y) * 0.293)
        if abs(next.x - look.x) > 0.001 || abs(next.y - look.y) > 0.001 { look = next }

        let leanTarget = CGSize(width: g.x, height: g.y + 0.7)
        let drifted = CGSize(width: lean.width + (leanTarget.width - lean.width) * 0.117,
                             height: lean.height + (leanTarget.height - lean.height) * 0.117)
        if abs(drifted.width - lean.width) > 0.001 || abs(drifted.height - lean.height) > 0.001 { lean = drifted }

        let now = Date()
        let r = motion.rotationRate, a = motion.userAcceleration
        if (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > 0.35 {
            if !surprised { blink(now) }
            surprisedUntil = now.addingTimeInterval(1.2)
        } else if (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() > 3 {
            blink(now)
        }
        let wide = now < surprisedUntil
        if wide != surprised { surprised = wide }
    }

    private func blink(_ now: Date) {
        guard now.timeIntervalSince(lastBlink) > 0.4 else { return }
        lastBlink = now
        blinks += 1
    }

    private static func clamp(_ v: Double) -> CGFloat { CGFloat(min(max(v, -1), 1)) }
}

extension View {
    /// A quick blink each time `trigger` changes, squashing about `anchor`.
    func blink(_ trigger: Int, anchor: UnitPoint = .center) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scaleY in
            view.scaleEffect(x: 1, y: scaleY, anchor: anchor)
        } keyframes: { _ in
            CubicKeyframe(0.06, duration: 0.07)
            CubicKeyframe(0.06, duration: 0.04)
            SpringKeyframe(1, duration: 0.18)
        }
    }
}

/// The eyes' answer to the phone, for one named group of a `VectorArtView`.
struct EyeResponse {
    /// Offset in the art's own units.
    var offset: CGPoint = .zero
    var blinks = 0
    /// Scale for the group (pupils shrink when surprised).
    var scale: CGFloat = 1
}

/// The water rings a floating card sends out (`Floating` in the earlier design), in ice to match the
/// glass. Under reduced motion there are none.
struct FloatRipples: View {
    var cornerRadius: CGFloat
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start) - delay
                let settled = min(max(t / 0.8, 0), 1)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let p = (max(0, t) / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(IrisPalette.ice, lineWidth: ((2 * (1 - p) + 0.5) * 2).rounded() / 2)
                            .opacity(0.22 * (1 - p) * settled)
                            .scaleEffect(x: 1 + p * 0.12, y: 1 + p * 0.3)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { start = .now }
        }
    }
}

/// Drifts a floating card downhill as the phone tilts and rocks it a little, the way the earlier design's
/// buttons floated on water. Reads the tilt itself, so only the card redraws as the phone moves.
struct TiltDrift: ViewModifier {
    var drift: CGFloat = 14
    private let tilt = DeviceTilt.shared

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(-tilt.lean.width * 4))
            .offset(x: tilt.lean.width * drift, y: tilt.lean.height * drift)
            .onAppear { tilt.start() }
            .onDisappear { tilt.stop() }
    }
}
