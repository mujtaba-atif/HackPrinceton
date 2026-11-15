import Foundation

/// Spoken coaching during the reach, so distance is heard in words, not only as which ear the tone is in.
///
/// Probe's step one was silent apart from the tone, and without headphones it was silent altogether, so
/// nothing told someone whose hand was in front of the object that it was still short of it. This says
/// how far to go, says plainly when the hand is in front of the object rather than at it, and says when
/// it has gone past. Lines come at most every `minimumGap` seconds, and only when the advice changes or
/// a reminder is due, so it never chants over the tone.
///
/// Never uses the word "back", or any of `LocateScreen.backKeywords`: `VoiceListener` would hear it
/// through the speaker as the command to leave the screen.
struct ReachCoach {
    enum Line: Equatable {
        /// The fingertip overlaps the object on screen but is still well short of it.
        case handInFront(inches: Int)
        case further(inches: Int)
        case almost(inches: Int)
        /// The hand has reached past the object's front.
        case overshot(inches: Int)
        /// A hand and the object are visible, but the hand's depth can't be read.
        case showFingers
        /// Only spoken without headphones, where there is no panned tone to follow.
        case lateral(towardRight: Bool)
    }

    struct Configuration {
        /// Matches `DistanceBeepController.depthTolerance`: inside it, step one is done.
        var tolerance: Float = 0.06
        var minimumGap: TimeInterval = 2.5
        var reminderInterval: TimeInterval = 5
        /// Inches the distance must change by to be worth saying again before a reminder is due.
        var significantChange = 3
        var almostInches = 4
        var unmeasuredGrace: TimeInterval = 4
        /// LiDAR readings of a moving finger are noisy; the median over this window is what's spoken.
        var smoothingWindow: TimeInterval = 0.6
    }

    var configuration = Configuration()

    private var recent: [(time: TimeInterval, gap: Float)] = []
    private var unmeasuredSince: TimeInterval?
    private var lastLine: Line?
    private var lastSpokenAt: TimeInterval = -.infinity
    private var explainedInFront = false

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func reset() {
        self = ReachCoach(configuration: configuration)
    }

    /// A new step began and announced itself: start its advice fresh, after its own line.
    mutating func stepChanged(at time: TimeInterval) {
        recent.removeAll()
        unmeasuredSince = nil
        lastLine = nil
        lastSpokenAt = time
    }

    /// Something else was said; keep the next line from landing straight after it.
    mutating func noteSpeech(at time: TimeInterval) {
        lastSpokenAt = time
    }

    /// Step one's advice for this measurement, if a line is due.
    /// - Parameters:
    ///   - gap: Object minus fingertip along the camera axis (meters); positive means reach further.
    ///   - handInFront: The fingertip overlaps the object on screen.
    mutating func depthLine(gap: Float?, handInFront: Bool, at time: TimeInterval) -> Line? {
        guard let gap else {
            recent.removeAll()
            let since = unmeasuredSince ?? time
            unmeasuredSince = since
            guard time - since >= configuration.unmeasuredGrace else { return nil }
            return due(.showFingers, at: time) ? .showFingers : nil
        }
        unmeasuredSince = nil
        recent.append((time, gap))
        recent.removeAll { time - $0.time > configuration.smoothingWindow }
        let smoothed = Self.median(recent.map(\.gap))
        guard abs(smoothed) > configuration.tolerance else { return nil }

        let inches = Self.inches(abs(smoothed))
        let line: Line
        if smoothed < 0 {
            line = .overshot(inches: inches)
        } else if handInFront, !explainedInFront {
            line = .handInFront(inches: inches)
        } else if inches <= configuration.almostInches {
            line = .almost(inches: inches)
        } else {
            line = .further(inches: inches)
        }
        return due(line, at: time) ? line : nil
    }

    /// Step two's advice without headphones, if a line is due. `dx` is object minus fingertip, across.
    func lateralLine(dx: Double, tolerance: Double, at time: TimeInterval) -> Line? {
        guard abs(dx) > tolerance else { return nil }
        let line = Line.lateral(towardRight: dx > 0)
        return due(line, at: time) ? line : nil
    }

    mutating func didSpeak(_ line: Line, at time: TimeInterval) {
        lastSpokenAt = time
        lastLine = line
        if case .handInFront = line { explainedInFront = true }
    }

    static func text(for line: Line, objectName: String) -> String {
        switch line {
        case let .handInFront(inches):
            "Your hand is in front of the \(objectName), not at it yet. Reach about \(distance(inches)) further."
        case let .further(inches):
            "Reach about \(distance(inches)) further."
        case .almost:
            "Almost there. Reach a little further."
        case let .overshot(inches):
            "You've gone past it. Bring your hand toward you about \(distance(inches))."
        case .showFingers:
            "Hold your hand open with your fingers apart, so I can tell how far it is."
        case let .lateral(towardRight):
            "Move your hand to your \(towardRight ? "right" : "left")."
        }
    }

    /// Rounded to 2 inches, never less than 2: "0 inches further" is not advice.
    static func inches(_ meters: Float) -> Int {
        max(2, Int((meters * 39.3701 / 2).rounded()) * 2)
    }

    static func distance(_ inches: Int) -> String {
        switch inches {
        case ..<12: "\(inches) inches"
        case 12..<18: "a foot"
        default: "\(Int((Double(inches) / 12).rounded())) feet"
        }
    }

    // MARK: Pacing

    private enum Kind: Equatable { case forward, overshot, showFingers, left, right }

    private static func kind(_ line: Line) -> Kind {
        switch line {
        case .handInFront, .further, .almost: .forward
        case .overshot: .overshot
        case .showFingers: .showFingers
        case let .lateral(towardRight): towardRight ? .right : .left
        }
    }

    private static func inches(of line: Line) -> Int? {
        switch line {
        case let .handInFront(inches), let .further(inches), let .almost(inches), let .overshot(inches): inches
        case .showFingers, .lateral: nil
        }
    }

    private func due(_ line: Line, at time: TimeInterval) -> Bool {
        guard time - lastSpokenAt >= configuration.minimumGap else { return false }
        guard let lastLine else { return true }
        if Self.kind(line) != Self.kind(lastLine) { return true }
        if let now = Self.inches(of: line), let before = Self.inches(of: lastLine),
           abs(now - before) >= configuration.significantChange {
            return true
        }
        return time - lastSpokenAt >= configuration.reminderInterval
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
