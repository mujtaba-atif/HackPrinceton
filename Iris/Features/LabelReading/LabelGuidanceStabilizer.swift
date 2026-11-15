import Foundation

/// Turns noisy per-frame decisions into a calm stream of spoken events.
///
/// - A decision must hold for `requiredStableFrames` consecutive frames before it is announced.
/// - The same event is never repeated within `minimumRepeatInterval`; standing instructions are re-prompted
///   every `reminderInterval`.
/// - While a turn is requested, the text's horizontal movement tells whether the user is turning
///   the right way ("Keep going") or the wrong way ("Other way").
/// - While searching for any text, each `sweepDuration` without text suggests turning the other way,
///   and `maximumSweeps` ends the attempt.
struct LabelGuidanceStabilizer: Sendable {
    struct Configuration: Sendable {
        var requiredStableFrames = 3
        var minimumRepeatInterval: TimeInterval = 2.5
        var reminderInterval: TimeInterval = 5
        var encouragementInterval: TimeInterval = 3
        var wrongWayDuration: TimeInterval = 1
        /// Minimum per-frame centroid movement counted as motion (centroid spans -1...1).
        var motionThreshold = 0.03
        /// Net centroid movement in the requested direction needed before "Keep going".
        var encouragementProgress = 0.15
        var sweepDuration: TimeInterval = 8
        var maximumSweeps = 2
    }

    var configuration = Configuration()
    private(set) var current: LabelGuidanceDecision?

    private var candidate: LabelGuidanceDecision?
    private var candidateCount = 0
    private var lastSpokenAt: TimeInterval = -.infinity
    private var lastSpokenEvent: LabelGuidanceEvent?
    private var previousCentroid: Double?
    private var wrongWayStart: (time: TimeInterval, centroid: Double)?
    private var progressSinceFeedback = 0.0
    private var searchingSince: TimeInterval?
    private var sweepsCompleted = 0

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func update(decision: LabelGuidanceDecision, readiness: LabelReadiness,
                         at time: TimeInterval) -> LabelGuidanceEvent? {
        if decision == candidate {
            candidateCount += 1
        } else {
            candidate = decision
            candidateCount = 1
        }

        if candidateCount >= configuration.requiredStableFrames, decision != current {
            current = decision
            previousCentroid = readiness.horizontalCentroid
            wrongWayStart = nil
            progressSinceFeedback = 0
            if decision == .searching {
                searchingSince = searchingSince ?? time
            } else {
                searchingSince = nil
                sweepsCompleted = 0
            }
            return emit(.instruct(decision), at: time)
        }

        guard let current else { return nil }

        switch current {
        case .searching:
            let since = searchingSince ?? time
            if time - since >= configuration.sweepDuration * Double(sweepsCompleted + 1) {
                sweepsCompleted += 1
                if sweepsCompleted >= configuration.maximumSweeps {
                    return emit(.noTextFound, at: time)
                }
                return emit(.trySweepOtherWay, at: time)
            }
            return remind(at: time)

        case .turnLeft, .turnRight:
            if let event = motionFeedback(for: current, readiness: readiness, at: time) {
                return event
            }
            return remind(at: time)

        case .moveCloser, .needsLight, .holdSteady:
            return remind(at: time)

        case .ready:
            return nil
        }
    }

    private mutating func motionFeedback(for decision: LabelGuidanceDecision, readiness: LabelReadiness,
                                         at time: TimeInterval) -> LabelGuidanceEvent? {
        guard let centroid = readiness.horizontalCentroid else {
            previousCentroid = nil
            wrongWayStart = nil
            return nil
        }
        defer { previousCentroid = centroid }
        guard let previous = previousCentroid else { return nil }

        // Turning left slides the visible text leftward (toward -1); turning right slides it toward +1.
        let expectedDirection: Double = decision == .turnLeft ? -1 : 1
        let progress = (centroid - previous) * expectedDirection
        // Net movement in the right direction; back-and-forth jitter cancels out.
        progressSinceFeedback = max(progressSinceFeedback + progress, 0)

        if progress > configuration.motionThreshold {
            wrongWayStart = nil
            if progressSinceFeedback >= configuration.encouragementProgress,
               time - lastSpokenAt >= configuration.encouragementInterval {
                progressSinceFeedback = 0
                return emit(.encourage, at: time)
            }
            return nil
        }

        if progress < -configuration.motionThreshold, wrongWayStart == nil {
            wrongWayStart = (time, previous)
        }
        if let start = wrongWayStart {
            let netProgress = (centroid - start.centroid) * expectedDirection
            if netProgress >= 0 {
                wrongWayStart = nil
            } else if time - start.time >= configuration.wrongWayDuration,
                      netProgress < -2 * configuration.motionThreshold {
                wrongWayStart = nil
                return emit(.wrongWay, at: time)
            }
        }
        return nil
    }

    private mutating func remind(at time: TimeInterval) -> LabelGuidanceEvent? {
        guard let current, time - lastSpokenAt >= configuration.reminderInterval else { return nil }
        return emit(.instruct(current), at: time)
    }

    /// Suppresses an exact repeat of the previous event inside `minimumRepeatInterval`.
    private mutating func emit(_ event: LabelGuidanceEvent, at time: TimeInterval) -> LabelGuidanceEvent? {
        if event == lastSpokenEvent, time - lastSpokenAt < configuration.minimumRepeatInterval {
            return nil
        }
        lastSpokenAt = time
        lastSpokenEvent = event
        return event
    }
}
