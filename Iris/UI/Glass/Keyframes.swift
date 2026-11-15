import SwiftUI

/// A CSS `cubic-bezier()` timing function. The design's motion is specified as CSS keyframes, and
/// porting it through this keeps every curve, overshoot included, exactly as designed.
struct Bezier: Sendable {
    let x1, y1, x2, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2)
    }

    static let linear = Bezier(0, 0, 1, 1)
    static let ease = Bezier(0.25, 0.1, 0.25, 1)
    static let easeIn = Bezier(0.42, 0, 1, 1)
    static let easeOut = Bezier(0, 0, 0.58, 1)
    static let easeInOut = Bezier(0.42, 0, 0.58, 1)

    /// The eased progress for a linear progress `x` (0…1). Can leave 0…1 when the curve overshoots.
    func callAsFunction(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        // Solve bx(t) = x: Newton first, bisection if it stalls.
        var t = x
        for _ in 0..<8 {
            let error = sample(t, x1, x2) - x
            if abs(error) < 1e-6 { return sample(t, y1, y2) }
            let slope = derivative(t, x1, x2)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var low = 0.0, high = 1.0
        t = x
        for _ in 0..<30 {
            let value = sample(t, x1, x2)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(t, y1, y2)
    }

    private func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private func derivative(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}

/// Where an animated element is: the CSS transform functions the design uses, in design points.
struct Pose: Sendable, Equatable {
    var x: Double = 0
    var y: Double = 0
    /// Degrees, clockwise.
    var rotation: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    var opacity: Double = 1
    var blur: Double = 0

    static let rest = Pose()

    init(x: Double = 0, y: Double = 0, rotation: Double = 0, scale: Double = 1, opacity: Double = 1, blur: Double = 0) {
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scaleX = scale
        self.scaleY = scale
        self.opacity = opacity
        self.blur = blur
    }

    init(x: Double = 0, y: Double = 0, rotation: Double = 0, scaleX: Double, scaleY: Double, opacity: Double = 1) {
        self.x = x
        self.y = y
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.opacity = opacity
    }

    func mix(_ other: Pose, _ t: Double) -> Pose {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        var pose = Pose()
        pose.x = lerp(x, other.x)
        pose.y = lerp(y, other.y)
        pose.rotation = lerp(rotation, other.rotation)
        pose.scaleX = lerp(scaleX, other.scaleX)
        pose.scaleY = lerp(scaleY, other.scaleY)
        pose.opacity = lerp(opacity, other.opacity)
        pose.blur = max(0, lerp(blur, other.blur))
        return pose
    }

    /// Two animations on one element (CSS `translate`/`scale` alongside `transform`).
    func combined(with other: Pose) -> Pose {
        var pose = Pose()
        pose.x = x + other.x
        pose.y = y + other.y
        pose.rotation = rotation + other.rotation
        pose.scaleX = scaleX * other.scaleX
        pose.scaleY = scaleY * other.scaleY
        pose.opacity = opacity * other.opacity
        pose.blur = blur + other.blur
        return pose
    }
}

/// One CSS animation: `@keyframes` plus its duration, delay, timing function, iteration count and
/// direction, always with `fill-mode: both`. As in CSS the timing function eases each keyframe interval.
struct Motion: Sendable {
    var duration: Double
    var delay: Double = 0
    var curve: Bezier = .ease
    var repeats = false
    var alternate = false
    var frames: [(at: Double, pose: Pose)]

    init(_ duration: Double, delay: Double = 0, curve: Bezier = .ease, repeats: Bool = false,
         alternate: Bool = false, _ frames: [(at: Double, pose: Pose)]) {
        self.duration = duration
        self.delay = delay
        self.curve = curve
        self.repeats = repeats
        self.alternate = alternate
        self.frames = frames
    }

    /// `from` → `to`, the common two-keyframe case.
    init(_ duration: Double, delay: Double = 0, curve: Bezier = .ease, repeats: Bool = false,
         alternate: Bool = false, from: Pose, to: Pose = .rest) {
        self.init(duration, delay: delay, curve: curve, repeats: repeats, alternate: alternate,
                  [(0, from), (1, to)])
    }

    /// Seconds from the start until it's over, `nil` while it loops forever.
    var end: Double? { repeats ? nil : delay + duration }

    /// The pose it rests in once it has finished, or under reduced motion: the last keyframe of a
    /// one-shot, no movement at all for a loop.
    var settled: Pose { repeats ? .rest : frames.last?.pose ?? .rest }

    func pose(at time: Double) -> Pose {
        guard let first = frames.first?.pose, let last = frames.last?.pose else { return .rest }
        let local = time - delay
        guard local > 0 else { return first }
        var iteration = (local / duration).rounded(.down)
        var progress = local / duration - iteration
        if !repeats, iteration >= 1 {
            iteration = 0
            progress = 1
            if !alternate { return last }
        }
        if alternate, Int(iteration) % 2 == 1 { progress = 1 - progress }
        return pose(progress: progress)
    }

    private func pose(progress: Double) -> Pose {
        var lower = frames[0]
        for frame in frames {
            if frame.at <= progress {
                lower = frame
            } else {
                let span = frame.at - lower.at
                guard span > 0 else { return frame.pose }
                return lower.pose.mix(frame.pose, curve((progress - lower.at) / span))
            }
        }
        return lower.pose
    }
}

extension View {
    /// Applies a pose: scale, then rotation, then translation, all about `anchor`. `unit` turns design
    /// points into screen points.
    func pose(_ pose: Pose, unit: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
        scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: anchor)
            .rotationEffect(.degrees(pose.rotation), anchor: anchor)
            .offset(x: pose.x * unit, y: pose.y * unit)
            .opacity(pose.opacity)
            .blur(radius: pose.blur * unit)
    }

    /// Plays `motions` (combined) from when this view appears, or from `since` so several views can share
    /// one clock. Under reduced motion the view sits in each motion's settled pose.
    func motion(_ motions: Motion..., unit: CGFloat = 1, anchor: UnitPoint = .center, since: Date? = nil) -> some View {
        modifier(MotionModifier(motions: motions, unit: unit, anchor: anchor, since: since))
    }

    func motion(_ motions: [Motion], unit: CGFloat = 1, anchor: UnitPoint = .center, since: Date? = nil) -> some View {
        modifier(MotionModifier(motions: motions, unit: unit, anchor: anchor, since: since))
    }
}

private struct MotionModifier: ViewModifier {
    let motions: [Motion]
    let unit: CGFloat
    let anchor: UnitPoint
    let since: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()
    @State private var finished = false

    private var start: Date { since ?? appeared }
    /// When the last of them stops, `nil` if any loops.
    private var end: Double? {
        var latest = 0.0
        for motion in motions {
            guard let end = motion.end else { return nil }
            latest = max(latest, end)
        }
        return latest
    }

    func body(content: Content) -> some View {
        if reduceMotion {
            content.pose(motions.reduce(Pose.rest) { $0.combined(with: $1.settled) }, unit: unit, anchor: anchor)
        } else {
            TimelineView(.animation(paused: finished)) { context in
                let t = context.date.timeIntervalSince(start)
                content.pose(motions.reduce(Pose.rest) { $0.combined(with: $1.pose(at: t)) }, unit: unit, anchor: anchor)
            }
            .onAppear { if since == nil { appeared = .now } }
            .task(id: since) {
                finished = false
                guard let end else { return }
                let remaining = end - Date().timeIntervalSince(start)
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining + 0.05)) }
                guard !Task.isCancelled else { return }
                finished = true
            }
        }
    }
}
