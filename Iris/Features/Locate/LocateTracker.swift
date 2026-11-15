import Combine
import CoreGraphics
import Foundation
import simd

/// Measures where the user's fingertips are relative to the target object, for `DistanceBeepController`.
///
/// This is Probe's `ObjectDetector` measurement step (fingertip → object edge, LiDAR depth gap, debounced
/// contact, then the approach to the camera) rebuilt on Iris's own services: Vision hand pose from
/// `HandTrackingService`, the YOLO target box from `ObjectDetectionService`, and LiDAR samples through
/// `DepthSampler`. Probe measured against a segmentation mask; Iris measures against the detection box,
/// so "inside the object" means inside its box. All points use Vision coordinates (normalized, upright
/// portrait, bottom-left origin), Probe's convention.
///
/// Iris change: the object's depth while reaching is read *around* the hand, never through it
/// (`ReachOcclusion`, `ObjectDepthMemory`). Read through it, a hand passing in front of the object put
/// the object at the hand's depth, which counted as a touch. With LiDAR, overlapping the object on
/// screen also no longer counts as contact without a depth measurement to back it.
@MainActor
final class LocateTracker: ObservableObject {
    // Probe's tuning, unchanged.
    static let readDistance: Float = 0.25     // meters (≈10 in)
    static let tooCloseDistance: Float = 0.15 // meters (≈6 in)
    private static let jointReach: [Float] = [0, 0.012, 0.03, 0.05]
    private let approachLostTimeout: TimeInterval = 2
    private let screenContactMargin: CGFloat = 0.02
    private let screenReleaseMargin: CGFloat = 0.06
    private let screenContactFingers = 2
    /// Fingertip depth patch, in normalized sensor units (≈9 depth pixels on a 256 × 192 LiDAR map).
    private let fingertipPatch: CGFloat = 0.035

    @Published private(set) var leftHandEdge: EdgeMeasurement?
    @Published private(set) var rightHandEdge: EdgeMeasurement?
    @Published private(set) var objectFound = false
    @Published private(set) var approaching = false
    @Published private(set) var objectCenter: CGPoint?
    @Published private(set) var cameraDistance: Float?
    @Published private(set) var objectClose = false

    private var foundTracker = FoundTracker()
    private var closeTracker = LocateTracker.makeCloseTracker()
    private var objectMemory = ObjectDepthMemory()
    /// The last target box, to notice the target switching to a different object.
    private var lastTargetBox: CGRect?
    /// When a depth measurement last put a fingertip within `nearReachDistance` of the object.
    private var lastNearReachAt: TimeInterval = -.infinity
    /// A real reading this close, this recently, lets screen overlap count as contact on LiDAR phones:
    /// a closing grip hides the fingertips and blocks LiDAR just as the hand arrives.
    private let nearReachDistance: Float = 0.12
    private let nearReachMemory: TimeInterval = 1
    private var lastObjectSeen: TimeInterval = 0
    private var lastJoints: [CGPoint] = []

    static func inches(_ meters: Float?) -> String {
        guard let meters else { return "—" }
        return String(format: "%.1f in", meters * 39.3701)
    }

    private static func makeCloseTracker() -> FoundTracker {
        var tracker = FoundTracker()
        tracker.contactDistance = readDistance
        tracker.releaseDistance = 0.30
        return tracker
    }

    func reset() {
        leftHandEdge = nil
        rightHandEdge = nil
        objectFound = false
        approaching = false
        objectCenter = nil
        cameraDistance = nil
        objectClose = false
        foundTracker = FoundTracker()
        closeTracker = Self.makeCloseTracker()
        objectMemory.reset()
        lastTargetBox = nil
        lastNearReachAt = -.infinity
        lastJoints = []
    }

    /// - Parameters:
    ///   - target: the object's current box (Vision coordinates), nil while it isn't detected.
    ///   - hands: tracked hands from `HandTrackingService` (top-left image coordinates).
    func update(frame: CameraFrame, target: CGRect?, hands: [HandObservation]) {
        update(depth: DepthFrame(cameraFrame: frame), cameraTransform: frame.cameraTransform,
               target: target, hands: hands)
    }

    /// The same, from the parts of a frame it uses, so tests can drive it with synthetic depth.
    func update(depth: DepthFrame, cameraTransform: simd_float4x4, target: CGRect?, hands: [HandObservation]) {
        let live = hands.filter { $0.state == .tracking || $0.state == .limited }.prefix(2)
        let handJoints = live.map { $0.landmarks.values.map { Self.vision($0.location) } }
        lastJoints = handJoints.flatMap { $0 }

        // Fingertip depths first: the object's depth is read around the hand, and needs to know how near it is.
        let fingersPerHand = live.map { hand in
            Self.fingers(of: hand).map { finger in (finger, self.depth(at: Self.depthPoint(of: finger), frame: depth)) }
        }
        let nearestHandDepth = fingersPerHand.joined().compactMap(\.1).min()
        // A box with no overlap with the last one, 0.1 s later, is a different object: forget the old one.
        if let target {
            if let lastTargetBox, DetectionGeometry.intersectionOverUnion(lastTargetBox, target) == 0 {
                objectMemory.reset()
            }
            lastTargetBox = target
        }
        // Straight off the box, for bringing the object to the camera: by then it is in the hand and moving.
        let liveObjectDepth = target.flatMap { objectDepth(in: $0, frame: depth) }
        let reachObjectDepth = target.flatMap {
            self.reachObjectDepth(in: $0, liveDepth: liveObjectDepth, hands: ReachOcclusion.handRegions(handJoints),
                                  nearestHandDepth: nearestHandDepth, frame: depth, cameraTransform: cameraTransform)
        }

        var perHand: [[EdgeMeasurement]] = []
        if let target {
            for fingers in fingersPerHand {
                perHand.append(fingers.map { finger, tipDepth in
                    measure(finger, tipDepth: tipDepth, target: target, objectDepth: reachObjectDepth, frame: depth)
                })
            }
        }
        let first = perHand.first.flatMap(closest)
        let second = perHand.count > 1 ? closest(perHand[1]) : nil
        // Probe labels the two hands left and right; which is which doesn't change the guidance. Compared
        // whole, not by fingertip alone: a still finger's distance changes as the depth reading does.
        if leftHandEdge != first { leftHandEdge = first }
        if rightHandEdge != second { rightHandEdge = second }

        var nearest = [first?.distance, second?.distance].compactMap { $0 }.min()
        if let nearest, nearest <= nearReachDistance { lastNearReachAt = depth.timestamp }
        // Overlap on screen stands in for contact on phones without LiDAR. With LiDAR, a hand in front of the
        // object overlaps it just the same, so overlap only counts right after depth showed the hand arriving.
        if nearest == nil, depth.depthMap == nil || depth.timestamp - lastNearReachAt <= nearReachMemory {
            nearest = screenContactDistance(hands: perHand)
        }
        // A gripping hand hides its fingertips and blocks LiDAR, so a hand still overlapping the object
        // keeps an existing `found`. It never starts one: a hand merely in front looks the same on screen.
        if nearest == nil, objectFound, let target, handOverlaps(target) {
            nearest = 0
        }
        let found = foundTracker.update(distance: nearest, time: depth.timestamp)
        if found != objectFound { objectFound = found }
        updateApproach(time: depth.timestamp, target: target, objectDepth: liveObjectDepth, frame: depth)
    }

    /// The object's depth for measuring the reach, never read through the hand.
    ///
    /// 1. No hand over the box: the usual box reading, which is also stored in `objectMemory`.
    /// 2. A hand over it: the stored position, projected into the current camera. It came from a clear
    ///    view, so it beats reading around the hand, which can catch the table in front or, once the
    ///    hand has gone past the object, mistake the object for the forearm.
    /// 3. A hand over it and nothing stored: the cells of the box clear of the hand.
    /// Otherwise nil, because a reading through the hand would put the object at the hand.
    private func reachObjectDepth(in box: CGRect, liveDepth: Float?, hands: [CGRect], nearestHandDepth: Float?,
                                  frame: DepthFrame, cameraTransform: simd_float4x4) -> Float? {
        func remembered() -> Float? {
            frame.isTrackingNormal ? objectMemory.axialDepth(cameraTransform: cameraTransform, at: frame.timestamp) : nil
        }
        guard ReachOcclusion.covers(box, hands: hands) else {
            if let liveDepth, frame.isTrackingNormal,
               let point = cameraPoint(at: CGPoint(x: box.midX, y: box.midY), depth: liveDepth, frame: frame) {
                objectMemory.remember(portraitPoint: point, cameraTransform: cameraTransform, at: frame.timestamp)
            }
            return liveDepth ?? remembered()
        }
        if let remembered = remembered() { return remembered }
        let cellDepths = ReachOcclusion.clearCells(of: box, avoiding: hands).compactMap { objectDepth(in: $0, frame: frame) }
        return ReachOcclusion.objectDepth(cellDepths: cellDepths, nearestHandDepth: nearestHandDepth)
    }

    // MARK: - Probe's approach step

    private func updateApproach(time: TimeInterval, target: CGRect?, objectDepth: Float?, frame: DepthFrame) {
        if objectFound, !approaching {
            approaching = true
            lastObjectSeen = time
        }
        guard approaching else { return }
        guard let target else {
            if time - lastObjectSeen >= approachLostTimeout {
                approaching = false
                objectCenter = nil
                cameraDistance = nil
                objectClose = false
                closeTracker = Self.makeCloseTracker()
            }
            return
        }
        lastObjectSeen = time
        let center = CGPoint(x: target.midX, y: target.midY)
        objectCenter = center
        cameraDistance = objectDepth.flatMap { depth in
            cameraPoint(at: center, depth: depth, frame: frame).map(simd_length)
        }
        let close = closeTracker.update(distance: cameraDistance, time: time)
        if close != objectClose { objectClose = close }
    }

    // MARK: - Measurements

    private struct Finger {
        let tip: CGPoint
        let dip: CGPoint?
        let reach: Float
    }

    /// Each finger's most distal confident joint (Vision often misses a tip pressed against an object),
    /// with the joint below it and how far that stand-in sits from the real fingertip.
    private static func fingers(of hand: HandObservation) -> [Finger] {
        HandJoint.fingerChains.compactMap { chain in
            guard let index = chain.firstIndex(where: { hand.landmarks[$0] != nil }),
                  let tip = hand.landmarks[chain[index]] else { return nil }
            let below = chain.dropFirst(index + 1).lazy.compactMap { hand.landmarks[$0] }.first
            return Finger(tip: vision(tip.location), dip: below.map { vision($0.location) },
                          reach: jointReach[min(index, jointReach.count - 1)])
        }
    }

    /// The tip sits at the very end of a thin finger, so a patch centered on it is half background.
    /// Its depth is read halfway down to the next joint instead, where a small patch is all finger.
    private static func depthPoint(of finger: Finger) -> CGPoint {
        finger.dip.map { CGPoint(x: (finger.tip.x + $0.x) / 2, y: (finger.tip.y + $0.y) / 2) } ?? finger.tip
    }

    private func measure(_ finger: Finger, tipDepth: Float?, target: CGRect, objectDepth: Float?,
                         frame: DepthFrame) -> EdgeMeasurement {
        let edge = Self.nearestEdge(to: finger.tip, of: target)
        let inside = target.contains(finger.tip)
        var distance: Float?
        var depthGap: Float?
        if let tipDepth, let objectDepth {
            if inside {
                depthGap = objectDepth - tipDepth - finger.reach
                distance = max(0, depthGap!)
            } else if let target3D = cameraPoint(at: edge, depth: objectDepth, frame: frame),
                      let hand3D = cameraPoint(at: finger.tip, depth: tipDepth, frame: frame) {
                distance = max(0, simd_distance(hand3D, target3D) - finger.reach)
                depthGap = target3D.z - hand3D.z - finger.reach
            }
        }
        return EdgeMeasurement(
            fingertip: finger.tip,
            edge: edge,
            distance: distance,
            insideMask: inside,
            screenGap: inside ? 0 : hypot(finger.tip.x - edge.x, finger.tip.y - edge.y),
            depthGap: depthGap,
            depthStatus: frame.depthMap == nil ? .noSensor
                : tipDepth == nil ? .handUnreadable
                : depthGap == nil ? .objectUnreadable : .measured
        )
    }

    /// Probe's `closestEdgeMeasurement`: the fingertip with a LiDAR reading if any has one, else the one
    /// nearest the object on screen.
    private func closest(_ measurements: [EdgeMeasurement]) -> EdgeMeasurement? {
        if let best = measurements.filter({ $0.distance != nil }).min(by: { $0.distance! < $1.distance! }) {
            return best
        }
        return measurements.min { $0.screenGap < $1.screenGap }
    }

    /// LiDAR-free stand-in distance from 2D overlap: 0 when one hand has enough fingertips on the object,
    /// the release distance when every fingertip is clearly away, nil (hold) in between.
    private func screenContactDistance(hands: [[EdgeMeasurement]]) -> Float? {
        let all = hands.flatMap { $0 }
        guard !all.isEmpty else { return nil }
        if hands.contains(where: { $0.filter { $0.screenGap <= screenContactMargin }.count >= screenContactFingers }) {
            return 0
        }
        if all.allSatisfy({ $0.screenGap > screenReleaseMargin }) {
            return foundTracker.releaseDistance
        }
        return nil
    }

    private func handOverlaps(_ target: CGRect) -> Bool {
        lastJoints.contains { joint in
            target.insetBy(dx: -screenContactMargin, dy: -screenContactMargin).contains(joint)
        }
    }

    // MARK: - Geometry and depth

    /// Hand-tracking points are top-left image coordinates; Probe's maths uses Vision's bottom-left.
    private static func vision(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1 - point.y)
    }

    /// The point on the box's outline nearest `point` (Probe's `nearestEdgePoint` for a mask).
    static func nearestEdge(to point: CGPoint, of box: CGRect) -> CGPoint {
        guard box.contains(point) else {
            return CGPoint(x: min(max(point.x, box.minX), box.maxX), y: min(max(point.y, box.minY), box.maxY))
        }
        let distances = [point.x - box.minX, box.maxX - point.x, point.y - box.minY, box.maxY - point.y]
        switch distances.enumerated().min(by: { $0.element < $1.element })?.offset {
        case 0: return CGPoint(x: box.minX, y: point.y)
        case 1: return CGPoint(x: box.maxX, y: point.y)
        case 2: return CGPoint(x: point.x, y: box.minY)
        default: return CGPoint(x: point.x, y: box.maxY)
        }
    }

    private func objectDepth(in box: CGRect, frame: DepthFrame) -> Float? {
        guard let clipped = DetectionGeometry.clippedUnitRect(box) else { return nil }
        if case let .measured(axial) = DepthSampler.sample(frame: frame, sensorRegion: DetectionGeometry.sensorRect(clipped)) {
            return Float(axial)
        }
        return nil
    }

    private func depth(at point: CGPoint, frame: DepthFrame) -> Float? {
        let half = fingertipPatch / 2
        let patch = CGRect(x: point.x - half, y: point.y - half, width: fingertipPatch, height: fingertipPatch)
        guard let clipped = DetectionGeometry.clippedUnitRect(patch) else { return nil }
        if case let .measured(axial) = DepthSampler.sample(frame: frame, sensorRegion: DetectionGeometry.sensorRect(clipped)) {
            return Float(axial)
        }
        return nil
    }

    /// Unprojects a Vision-coordinates point at an axial depth into portrait camera space (meters).
    private func cameraPoint(at point: CGPoint, depth: Float, frame: DepthFrame) -> SIMD3<Float>? {
        let sensor = DetectionGeometry.sensorRect(CGRect(x: point.x, y: point.y, width: 0, height: 0)).origin
        guard let ray = DepthGeometry.portraitRay(sensorPoint: sensor, frame: frame) else { return nil }
        return SIMD3<Float>(Float(ray.x), Float(ray.y), Float(ray.z)) * depth
    }
}
