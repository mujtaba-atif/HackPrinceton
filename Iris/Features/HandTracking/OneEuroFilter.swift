import CoreGraphics
import Foundation

/// One Euro filter (Casiez et al., 2012): a speed-adaptive low-pass filter.
/// At rest the cutoff stays low (strong jitter suppression); during fast motion it rises (low lag).
struct OneEuroFilter: Sendable {
    var minCutoff: Double
    var beta: Double
    var derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative: Double = 0
    private var previousTimestamp: TimeInterval?

    init(minCutoff: Double = 1.2, beta: Double = 0.02, derivativeCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func filter(_ value: Double, timestamp: TimeInterval) -> Double {
        guard let previousValue, let previousTimestamp, timestamp > previousTimestamp else {
            self.previousValue = value
            self.previousTimestamp = timestamp
            return value
        }
        let dt = timestamp - previousTimestamp
        let derivative = (value - previousValue) / dt
        let smoothedDerivative = Self.lerp(previousDerivative, derivative,
                                           alpha: Self.alpha(cutoff: derivativeCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let smoothed = Self.lerp(previousValue, value, alpha: Self.alpha(cutoff: cutoff, dt: dt))

        self.previousValue = smoothed
        self.previousDerivative = smoothedDerivative
        self.previousTimestamp = timestamp
        return smoothed
    }

    mutating func reset() {
        previousValue = nil
        previousDerivative = 0
        previousTimestamp = nil
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    private static func lerp(_ a: Double, _ b: Double, alpha: Double) -> Double {
        a + alpha * (b - a)
    }
}

/// Two independent One Euro filters for a normalized 2D point.
struct OneEuroPointFilter: Sendable {
    private var x: OneEuroFilter
    private var y: OneEuroFilter

    init(minCutoff: Double = 1.2, beta: Double = 0.02, derivativeCutoff: Double = 1) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
    }

    mutating func filter(_ point: CGPoint, timestamp: TimeInterval) -> CGPoint {
        CGPoint(x: x.filter(point.x, timestamp: timestamp), y: y.filter(point.y, timestamp: timestamp))
    }

    mutating func reset() {
        x.reset()
        y.reset()
    }
}
