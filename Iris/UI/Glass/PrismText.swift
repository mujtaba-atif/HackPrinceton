import SwiftUI

/// The design's entry-only letter reveal: each glyph rises into focus while a blue / soft-violet / ice
/// light travels down through it, then it settles to white. It plays once, on appear. Under reduced
/// motion the final white text shows straight away. VoiceOver reads the phrase as one.
struct PrismText: View {
    struct Timing {
        var delay: Double
        var step: Double
        var lift: Double
        var blur: Double
        var duration: Double

        static let brand = Timing(delay: 0.12, step: 0.075, lift: 12, blur: 5, duration: 2.1)
        static let tagline = Timing(delay: 0.45, step: 0.022, lift: 6, blur: 3, duration: 1.8)
        static let question = Timing(delay: 0.12, step: 0.018, lift: 7, blur: 3, duration: 1.65)
    }

    var text: String
    var font: Font
    /// CSS letter-spacing, design points.
    var tracking: CGFloat = 0
    var timing: Timing
    /// Starts a new line before this word (0-based), as the options question does.
    var breakBeforeWord: Int?
    var lineSpacing: CGFloat = 0
    var unit: CGFloat = 1
    /// Once the light has settled, each letter does one jelly hop in a wave (crouch, jump, squash, wobble),
    /// the title's flourish from the earlier design. Once only: the design allows no repeating text motion.
    var hops = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false

    private static let arrive = Bezier(0.2, 0.7, 0.25, 1)
    private static let light = Bezier(0.25, 0.1, 0.3, 1)
    /// The text-clipped gradient, top to bottom, drawn 3.6 times the glyph's height (sRGB hex).
    private static let prism: [(Double, UInt32)] = [
        (0, 0xFAFCFF), (0.18, 0xFAFCFF), (0.31, 0xA6DFFF), (0.44, 0xB9B8FF), (0.57, 0xE7F5FF),
        (0.72, 0xFAFCFF), (1, 0xFAFCFF),
    ]

    /// Lines of glyphs with their running index.
    private var lines: [[(index: Int, char: Character)]] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var lines: [[(Int, Character)]] = [[]]
        var index = 0
        for (w, word) in words.enumerated() {
            if w == breakBeforeWord, w > 0 {
                lines.append([])
            } else if w > 0 {
                lines[lines.count - 1].append((-1, " "))
            }
            for char in word {
                lines[lines.count - 1].append((index, char))
                index += 1
            }
        }
        return lines
    }

    private var total: Double {
        timing.delay + Double(text.count) * timing.step + max(0.78, timing.duration)
    }

    var body: some View {
        Group {
            if reduceMotion || finished {
                glyphs { _ in nil }
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    glyphs { index in index < 0 ? nil : t - timing.delay - Double(index) * timing.step }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear { start = .now }
        .task {
            try? await Task.sleep(for: .seconds(total))
            finished = true
        }
    }

    /// `time(index)` is the seconds since that glyph started, `nil` for settled.
    private func glyphs(_ time: @escaping (Int) -> Double?) -> some View {
        VStack(spacing: lineSpacing * unit) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: tracking * unit) {
                    ForEach(Array(line.enumerated()), id: \.offset) { _, glyph in
                        glyphView(glyph.char, time(glyph.index), index: glyph.index)
                    }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func glyphView(_ char: Character, _ t: Double?, index: Int) -> some View {
        let text = Text(String(char)).font(font)
        if let t {
            let arrive = Self.arrive(min(1, max(0, t / 0.78)))
            let light = Self.light(min(1, max(0, t / timing.duration)))
            text
                .foregroundStyle(gradient(at: light))
                .opacity(t <= 0 ? 0 : arrive)
                .offset(y: (1 - arrive) * timing.lift * unit)
                .blur(radius: (1 - arrive) * timing.blur * unit)
        } else if hops, !reduceMotion, index >= 0 {
            text.foregroundStyle(IrisPalette.white)
                .modifier(JellyHop(delay: Double(index) * 0.1, height: 16 * unit))
        } else {
            text.foregroundStyle(IrisPalette.white)
        }
    }

    /// The part of the tall gradient showing through a glyph when the light is `position` (0…1) of the
    /// way down.
    private func gradient(at position: Double) -> LinearGradient {
        let window = 1 / 3.6
        let top = position * (1 - window)
        let samples = 7
        let stops = (0..<samples).map { i -> Gradient.Stop in
            let local = Double(i) / Double(samples - 1)
            return Gradient.Stop(color: Self.color(at: top + local * window), location: local)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    private static func color(at y: Double) -> Color {
        var lower = prism[0]
        for stop in prism {
            if stop.0 >= y {
                let span = stop.0 - lower.0
                return mix(lower.1, stop.1, span > 0 ? (y - lower.0) / span : 1)
            }
            lower = stop
        }
        return Color(hex: lower.1)
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) / 255 }
        func lerp(_ shift: UInt32) -> Double { channel(a, shift) + (channel(b, shift) - channel(a, shift)) * t }
        return Color(.sRGB, red: lerp(16), green: lerp(8), blue: lerp(0))
    }
}

/// One jelly hop: crouch, take off stretched, squash on landing and wobble back. Plays on appear.
private struct JellyHop: ViewModifier {
    var delay: Double
    var height: CGFloat

    struct Pose {
        var y: CGFloat = 0
        /// > 1 tall and thin, < 1 short and wide.
        var stretch: CGFloat = 1
    }

    @State private var trigger = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Pose(), trigger: trigger) { view, pose in
                view
                    .scaleEffect(x: 1 / pose.stretch.squareRoot(), y: pose.stretch, anchor: .bottom)
                    .offset(y: pose.y)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    LinearKeyframe(0, duration: delay + 0.12)
                    CubicKeyframe(-height, duration: 0.26)
                    CubicKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.stretch) {
                    LinearKeyframe(1, duration: delay)
                    CubicKeyframe(0.8, duration: 0.12)
                    CubicKeyframe(1.15, duration: 0.12)
                    CubicKeyframe(1, duration: 0.14)
                    CubicKeyframe(1.08, duration: 0.22)
                    CubicKeyframe(0.8, duration: 0.08)
                    SpringKeyframe(1, duration: 0.9, spring: .bouncy(duration: 0.4, extraBounce: 0.2))
                }
            }
            .onAppear { trigger += 1 }
    }
}
