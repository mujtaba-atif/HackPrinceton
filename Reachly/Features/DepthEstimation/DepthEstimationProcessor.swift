import Foundation

struct DepthSmoother {
    private var previous: (id: UUID, timestamp: TimeInterval, depth: Double)?

    mutating func reset() { previous = nil }

    mutating func update(_ depth: Double, objectID: UUID, timestamp: TimeInterval) -> Double {
        var filtered = depth
        if let previous, previous.id == objectID {
            let elapsed = timestamp - previous.timestamp
            // Do not interpolate across loss, time reversal, or a sudden change of surface.
            if elapsed > 0, elapsed <= 0.5, abs(depth - previous.depth) <= max(0.2, previous.depth * 0.25) {
                let alpha = 1 - exp(-elapsed / 0.25)
                filtered = previous.depth + alpha * (depth - previous.depth)
            }
        }
        previous = (objectID, timestamp, filtered)
        return filtered
    }
}

/// Bounded depth-only history pairs a delayed Vision observation with its exact capture frame.
/// Dropped/missing matches are unavailable; a newer depth map is never substituted.
struct DepthEstimationProcessor {
    static let maximumAge: TimeInterval = 0.5
    static let historyLimit = 60
    private(set) var frames: [DepthFrame] = []
    private var smoother = DepthSmoother()
    private var lastTarget: SelectedObjectTarget?
    private var lastEstimate: SpatialTargetEstimate?

    mutating func process(_ frame: DepthFrame, target: SelectedObjectTarget?,
                          supportsSceneDepth: Bool) -> SpatialTargetEstimate? {
        if let last = frames.last, frame.timestamp <= last.timestamp {
            frames = []
            invalidate()
        }
        frames.append(frame)
        frames.removeAll { frame.timestamp - $0.timestamp > ObjectDetectionState.retentionInterval }
        if frames.count > Self.historyLimit { frames.removeFirst(frames.count - Self.historyLimit) }

        // Limited tracking invalidates history even if no target is currently selected.
        if !frame.isTrackingNormal { frames = [] }
        guard let target else {
            invalidate()
            return nil
        }
        func unavailable(_ reason: DepthUnavailableReason) -> SpatialTargetEstimate {
            .unavailable(objectID: target.object.id, reason: reason, timestamp: target.lastSeenTimestamp)
        }
        guard target.state == .tracking else {
            invalidate()
            return unavailable(.targetLost)
        }
        guard frame.isTrackingNormal else {
            invalidate()
            return unavailable(.trackingLimited)
        }
        let age = frame.timestamp - target.lastSeenTimestamp
        guard age >= -0.001, age <= Self.maximumAge else {
            invalidate()
            return unavailable(.staleObservation)
        }
        guard let matched = frames.first(where: { abs($0.timestamp - target.lastSeenTimestamp) < 0.001 }) else {
            invalidate()
            return unavailable(supportsSceneDepth ? .unmatchedFrame : .unsupportedDevice)
        }
        guard matched.isTrackingNormal,
              let region = DepthGeometry.sensorRegion(for: target, imageResolution: matched.imageResolution),
              let ray = DepthGeometry.portraitRay(sensorPoint: .init(x: region.midX, y: region.midY), frame: matched) else {
            invalidate()
            return unavailable(.invalidGeometry)
        }

        // Direction is calibrated 2D bearing, and remains useful without metric depth.
        func directionalUnavailable(_ reason: DepthUnavailableReason) -> SpatialTargetEstimate {
            DepthGeometry.estimate(objectID: target.object.id, ray: ray, axialDepth: nil,
                                   validity: .unavailable(reason), timestamp: matched.timestamp)
        }
        guard supportsSceneDepth else {
            invalidate()
            return directionalUnavailable(.unsupportedDevice)
        }
        guard frame.depthMap != nil else {
            invalidate()
            return directionalUnavailable(.missingDepth)
        }
        if lastTarget == target, let lastEstimate { return lastEstimate }

        let estimate: SpatialTargetEstimate
        switch DepthSampler.sample(frame: matched, sensorRegion: region) {
        case let .measured(depth):
            let filtered = smoother.update(depth, objectID: target.object.id, timestamp: matched.timestamp)
            estimate = DepthGeometry.estimate(objectID: target.object.id, ray: ray, axialDepth: filtered,
                                             validity: .measured, timestamp: matched.timestamp)
        case let .unavailable(reason):
            smoother.reset()
            estimate = directionalUnavailable(reason)
        }
        lastTarget = target
        lastEstimate = estimate
        return estimate
    }

    private mutating func invalidate() {
        smoother.reset()
        lastTarget = nil
        lastEstimate = nil
    }
}

/// CPU sampling, sorting, history, and smoothing stay isolated from the main actor.
actor DepthEstimationWorker {
    private var processor = DepthEstimationProcessor()

    func process(_ frame: DepthFrame, target: SelectedObjectTarget?,
                 supportsSceneDepth: Bool) -> SpatialTargetEstimate? {
        processor.process(frame, target: target, supportsSceneDepth: supportsSceneDepth)
    }
}
