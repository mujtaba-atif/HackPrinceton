import CoreGraphics
import Foundation

/// Pure state reducer: associates raw per-frame poses with stable tracks, smooths them,
/// and classifies tracking quality. Contains no Vision or UI code so it is fully unit-testable.
struct HandTrackingReducer {
    /// How long a missing hand keeps its last smoothed pose (as `.lost`) before being dropped.
    static let lostGraceInterval: TimeInterval = 0.4
    /// A track not updated for this long is considered lost even if no new frame arrived.
    static let staleInterval: TimeInterval = 0.2
    /// Maximum normalized center movement between frames that still counts as the same hand.
    static let maximumMatchDistance: CGFloat = 0.25
    static let minimumUsableConfidence: Double = 0.5
    static let minimumUsableJointCount = 6

    private struct Track {
        let id: UUID
        var chirality: HandChirality
        var jointFilters: [HandJoint: OneEuroPointFilter] = [:]
        var centerFilter = OneEuroPointFilter()
        var observation: HandObservation
        var lastSeen: TimeInterval { observation.lastSeen }

        mutating func resetFilters() {
            jointFilters.removeAll()
            centerFilter.reset()
        }
    }

    private var tracks: [Track] = []
    private(set) var snapshot = HandTrackingSnapshot()

    mutating func update(_ poses: [RawHandPose], timestamp: TimeInterval, imageSize: CGSize) {
        guard timestamp.isFinite, snapshot.timestamp.map({ timestamp > $0 }) ?? true else { return }

        var available = tracks.filter { timestamp - $0.lastSeen <= Self.lostGraceInterval }
        var updated: [Track] = []

        // Most complete poses claim tracks first.
        for pose in poses.sorted(by: { $0.landmarks.count > $1.landmarks.count }) {
            guard let rawCenter = Self.center(of: pose.landmarks) else { continue }
            var track: Track
            if let index = Self.bestMatch(for: pose, center: rawCenter, in: available) {
                track = available.remove(at: index)
                if timestamp - track.lastSeen > Self.staleInterval {
                    // Re-acquired after a dropout: stale filter history would only add lag.
                    track.resetFilters()
                }
                if pose.chirality != .unknown { track.chirality = pose.chirality }
            } else {
                track = Track(id: UUID(), chirality: pose.chirality,
                              observation: Self.placeholder(timestamp: timestamp))
            }
            track.observation = Self.smooth(pose, rawCenter: rawCenter, track: &track, timestamp: timestamp)
            updated.append(track)
            if updated.count == 2 { break }
        }

        // Unmatched but recent tracks coast as `.lost` through brief dropouts.
        let coasting = available.map { track -> Track in
            var track = track
            track.observation = Self.relabel(track.observation, state: .lost, timestamp: timestamp)
            return track
        }

        tracks = Self.stableOrder(updated + coasting, previous: tracks)
        snapshot.hands = tracks.map(\.observation)
        snapshot.timestamp = timestamp
        snapshot.uprightImageSize = imageSize
        snapshot.isSuspended = false
    }

    /// Called by a watchdog so a stalled frame stream cannot leave a stale "tracked" hand on screen.
    mutating func expire(at now: TimeInterval) {
        guard !snapshot.isSuspended else { return }
        var changed = false
        tracks = tracks.compactMap { track in
            let age = now - track.lastSeen
            if age > Self.lostGraceInterval {
                changed = true
                return nil
            }
            if age > Self.staleInterval, track.observation.state != .lost {
                var track = track
                track.observation = Self.relabel(track.observation, state: .lost, timestamp: track.observation.timestamp)
                changed = true
                return track
            }
            return track
        }
        if changed { snapshot.hands = tracks.map(\.observation) }
    }

    /// Marks the reducer active before the first frame arrives (state becomes `.searching`).
    mutating func resume() {
        snapshot.isSuspended = false
    }

    /// Clears all tracks; used when the camera pauses, is interrupted, or stops.
    mutating func suspend() {
        tracks = []
        snapshot = HandTrackingSnapshot(uprightImageSize: snapshot.uprightImageSize, isSuspended: true)
    }

    // MARK: - Helpers

    /// Palm center: middle knuckle, else the mean of wrist and knuckles, else all joints.
    static func center(of landmarks: [HandJoint: HandLandmark]) -> CGPoint? {
        if let middle = landmarks[.middleMCP] { return middle.location }
        let palm = ([HandJoint.wrist] + HandJoint.knuckles).compactMap { landmarks[$0]?.location }
        if let mean = mean(palm) { return mean }
        return mean(landmarks.values.map(\.location))
    }

    /// The most distal detected joint on a finger chain (the tip, or its stand-in when hidden).
    static func distalPoint(of chain: [HandJoint], in landmarks: [HandJoint: HandLandmark]) -> CGPoint? {
        chain.lazy.compactMap { landmarks[$0]?.location }.first
    }

    static func pointingTip(in landmarks: [HandJoint: HandLandmark]) -> CGPoint? {
        let index = HandJoint.fingerChains[1]
        if let tip = distalPoint(of: index, in: landmarks) { return tip }
        // Fall back to any detected fingertip, preferring the longer fingers.
        for chain in [HandJoint.fingerChains[2], HandJoint.fingerChains[3], HandJoint.fingerChains[4], HandJoint.fingerChains[0]] {
            if let tip = landmarks[chain[0]]?.location { return tip }
        }
        return nil
    }

    private static func bestMatch(for pose: RawHandPose, center: CGPoint, in tracks: [Track]) -> Int? {
        var best: (index: Int, cost: CGFloat)?
        for (index, track) in tracks.enumerated() {
            let conflicting = pose.chirality != .unknown && track.chirality != .unknown && pose.chirality != track.chirality
            let distance = HandGeometry.distance(center, track.observation.center)
            guard distance <= maximumMatchDistance else { continue }
            // Vision's chirality can flicker, so a mismatch is a penalty rather than a veto.
            let cost = distance + (conflicting ? 0.15 : 0)
            if best.map({ cost < $0.cost }) ?? true { best = (index, cost) }
        }
        return best?.index
    }

    private static func smooth(_ pose: RawHandPose, rawCenter: CGPoint, track: inout Track,
                               timestamp: TimeInterval) -> HandObservation {
        var smoothed: [HandJoint: HandLandmark] = [:]
        for (joint, landmark) in pose.landmarks {
            var filter = track.jointFilters[joint] ?? OneEuroPointFilter()
            let location = filter.filter(landmark.location, timestamp: timestamp)
            track.jointFilters[joint] = filter
            smoothed[joint] = HandLandmark(joint: joint, location: clamp(location), confidence: landmark.confidence)
        }
        // Joints Vision stopped reporting would resume from stale history; forget them.
        for joint in track.jointFilters.keys where pose.landmarks[joint] == nil {
            track.jointFilters[joint] = nil
        }
        let center = clamp(track.centerFilter.filter(rawCenter, timestamp: timestamp))
        let confidence = pose.landmarks.values.reduce(0) { $0 + $1.confidence } / Double(HandJoint.allCases.count)
        let usable = confidence >= minimumUsableConfidence && pose.landmarks.count >= minimumUsableJointCount

        return HandObservation(
            id: track.id,
            chirality: track.chirality,
            landmarks: smoothed,
            center: center,
            indexTip: distalPoint(of: HandJoint.fingerChains[1], in: smoothed),
            pointingTip: pointingTip(in: smoothed),
            confidence: confidence,
            state: usable ? .tracking : .limited,
            timestamp: timestamp,
            lastSeen: timestamp
        )
    }

    private static func relabel(_ observation: HandObservation, state: HandTrackingState,
                                timestamp: TimeInterval) -> HandObservation {
        HandObservation(id: observation.id, chirality: observation.chirality, landmarks: observation.landmarks,
                        center: observation.center, indexTip: observation.indexTip,
                        pointingTip: observation.pointingTip, confidence: observation.confidence,
                        state: state, timestamp: timestamp, lastSeen: observation.lastSeen)
    }

    private static func placeholder(timestamp: TimeInterval) -> HandObservation {
        HandObservation(id: UUID(), chirality: .unknown, landmarks: [:], center: .zero, indexTip: nil,
                        pointingTip: nil, confidence: 0, state: .searching, timestamp: timestamp, lastSeen: timestamp)
    }

    /// Keeps hands in a consistent order across frames so overlays and VoiceOver do not reshuffle.
    private static func stableOrder(_ current: [Track], previous: [Track]) -> [Track] {
        let oldIDs = previous.map(\.id)
        return current.sorted {
            (oldIDs.firstIndex(of: $0.id) ?? Int.max) < (oldIDs.firstIndex(of: $1.id) ?? Int.max)
        }
    }

    private static func mean(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}
