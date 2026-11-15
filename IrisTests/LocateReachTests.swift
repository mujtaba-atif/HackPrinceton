import XCTest
import CoreVideo
import simd
@testable import Iris

// MARK: - Object depth memory

final class ObjectDepthMemoryTests: XCTestCase {
    private let intrinsics = simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(200, 150, 1)))
    private let resolution = CGSize(width: 400, height: 300)

    /// The portrait → ARKit camera conversion must agree with ARKit's own pinhole projection, or the
    /// remembered object would be re-projected to the wrong depth when the phone moves.
    func testPortraitToCameraSpaceMatchesPinholeProjection() throws {
        let frame = DepthFrame(depthMap: nil, confidenceMap: nil, timestamp: 0, intrinsics: intrinsics,
                               imageResolution: resolution, isTrackingNormal: true)
        let sensor = CGPoint(x: 0.8, y: 0.3)
        let ray = try XCTUnwrap(DepthGeometry.portraitRay(sensorPoint: sensor, frame: frame))
        let portrait = SIMD3<Float>(Float(ray.x), Float(ray.y), Float(ray.z)) * 0.7
        let camera = ObjectDepthMemory.cameraSpace(fromPortrait: portrait)
        // ARKit camera space looks down -z; u = fx·X/(-Z) + cx, v = fy·(-Y)/(-Z) + cy.
        let u = 200 * camera.x / -camera.z + 200
        let v = 200 * -camera.y / -camera.z + 150
        XCTAssertEqual(Double(u) / 400, sensor.x, accuracy: 0.0001)
        XCTAssertEqual(Double(v) / 300, sensor.y, accuracy: 0.0001)
        XCTAssertEqual(-camera.z, 0.7, accuracy: 0.0001)
        let back = ObjectDepthMemory.portraitSpace(fromCamera: camera)
        XCTAssertEqual(simd_distance(back, portrait), 0, accuracy: 0.0001)
    }

    func testRememberedDepthFollowsThePhoneMovingCloser() throws {
        var memory = ObjectDepthMemory()
        memory.remember(portraitPoint: SIMD3(0.05, 0, 0.6), cameraTransform: matrix_identity_float4x4, at: 1)
        XCTAssertEqual(try XCTUnwrap(memory.axialDepth(cameraTransform: matrix_identity_float4x4, at: 2)),
                       0.6, accuracy: 0.0001)
        // The camera looks down world -z; moving 10 cm that way brings the object 10 cm nearer.
        var moved = matrix_identity_float4x4
        moved.columns.3 = SIMD4(0, 0, -0.1, 1)
        XCTAssertEqual(try XCTUnwrap(memory.axialDepth(cameraTransform: moved, at: 2)), 0.5, accuracy: 0.0001)
    }

    func testMemoryExpiresAndJumpsReplaceInsteadOfBlending() throws {
        var memory = ObjectDepthMemory()
        memory.remember(portraitPoint: SIMD3(0, 0, 0.6), cameraTransform: matrix_identity_float4x4, at: 1)
        XCTAssertNil(memory.axialDepth(cameraTransform: matrix_identity_float4x4, at: 1 + memory.maximumAge + 1))

        memory.remember(portraitPoint: SIMD3(0, 0, 0.62), cameraTransform: matrix_identity_float4x4, at: 2)
        let blended = try XCTUnwrap(memory.axialDepth(cameraTransform: matrix_identity_float4x4, at: 2))
        XCTAssertGreaterThan(blended, 0.6)
        XCTAssertLessThan(blended, 0.62)

        memory.remember(portraitPoint: SIMD3(0, 0, 1.2), cameraTransform: matrix_identity_float4x4, at: 3)
        XCTAssertEqual(try XCTUnwrap(memory.axialDepth(cameraTransform: matrix_identity_float4x4, at: 3)),
                       1.2, accuracy: 0.0001)
    }
}

// MARK: - Reading around the hand

final class ReachOcclusionTests: XCTestCase {
    func testMostAgreedSurfaceIsTheObjectNotTheWallBehindIt() {
        let depth = ReachOcclusion.objectDepth(cellDepths: [2.0, 0.61, 0.6, 0.62, 2.05], nearestHandDepth: 0.35)
        XCTAssertEqual(try XCTUnwrap(depth), 0.61, accuracy: 0.001)
    }

    /// The bottom cells of a tabletop object's box are the table in front of it, nearer than the object.
    func testTableInFrontIsNotMistakenForTheObject() {
        let depth = ReachOcclusion.objectDepth(cellDepths: [0.45, 0.46, 0.6, 0.61, 0.62, 2.0], nearestHandDepth: 0.35)
        XCTAssertEqual(try XCTUnwrap(depth), 0.61, accuracy: 0.001)
    }

    func testTieGoesToTheNearerSurface() {
        let depth = ReachOcclusion.objectDepth(cellDepths: [0.6, 0.61, 2.0, 2.01], nearestHandDepth: nil)
        XCTAssertEqual(try XCTUnwrap(depth), 0.605, accuracy: 0.001)
    }

    func testForearmNearerThanTheFingertipsIsIgnored() {
        let depth = ReachOcclusion.objectDepth(cellDepths: [0.2, 0.21, 0.6, 0.62], nearestHandDepth: 0.35)
        XCTAssertEqual(try XCTUnwrap(depth), 0.61, accuracy: 0.001)
    }

    func testOneCellIsNotEnough() {
        XCTAssertNil(ReachOcclusion.objectDepth(cellDepths: [0.6], nearestHandDepth: nil))
        XCTAssertNil(ReachOcclusion.objectDepth(cellDepths: [0.6, 1.5], nearestHandDepth: nil))
    }

    func testCoverageAndClearCells() {
        let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        XCTAssertFalse(ReachOcclusion.covers(box, hands: []))
        XCTAssertFalse(ReachOcclusion.covers(box, hands: [CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1)]))
        let hand = CGRect(x: 0.45, y: 0.3, width: 0.1, height: 0.4)
        XCTAssertTrue(ReachOcclusion.covers(box, hands: [hand]))
        let cells = ReachOcclusion.clearCells(of: box, avoiding: [hand])
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(cells.allSatisfy { !$0.intersects(hand) && box.insetBy(dx: -1e-9, dy: -1e-9).contains($0) })
        XCTAssertEqual(ReachOcclusion.clearCells(of: box, avoiding: []).count, 16)
    }

    func testHandRegionIsPaddedJointBox() throws {
        let region = try XCTUnwrap(ReachOcclusion.handRegions([[CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.6, y: 0.5)]],
                                                              padding: 0.05).first)
        XCTAssertEqual(region.minX, 0.45, accuracy: 0.0001)
        XCTAssertEqual(region.maxY, 0.55, accuracy: 0.0001)
        XCTAssertTrue(ReachOcclusion.handRegions([[]]).isEmpty)
    }
}

// MARK: - Tracker: hand in front of the object vs touching it

@MainActor
final class LocateTrackerReachTests: XCTestCase {
    private let intrinsics = simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(200, 150, 1)))
    private let resolution = CGSize(width: 400, height: 300)
    private let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    private let objectDepth: Float = 0.6
    private let wallDepth: Float = 2.0

    /// A LiDAR-sized depth map painted in Vision coordinates: `surface` returns the depth at a point.
    private func depthFrame(at time: TimeInterval, hasDepth: Bool = true, confident: Bool = true,
                            surface: (CGPoint) -> Float) throws -> DepthFrame {
        let width = 256, height = 192
        var depth: CVPixelBuffer?
        var levels: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DepthFloat32,
                                           nil, &depth), kCVReturnSuccess)
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8,
                                           nil, &levels), kCVReturnSuccess)
        let depthMap = try XCTUnwrap(depth), confidenceMap = try XCTUnwrap(levels)
        CVPixelBufferLockBaseAddress(depthMap, [])
        CVPixelBufferLockBaseAddress(confidenceMap, [])
        let depths = try XCTUnwrap(CVPixelBufferGetBaseAddress(depthMap)).assumingMemoryBound(to: Float.self)
        let confidences = try XCTUnwrap(CVPixelBufferGetBaseAddress(confidenceMap)).assumingMemoryBound(to: UInt8.self)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float>.stride
        let confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
        for y in 0..<height {
            for x in 0..<width {
                // Native sensor → upright Vision: the inverse of `DetectionGeometry.sensorRect`.
                let sensorX = (Double(x) + 0.5) / Double(width), sensorY = (Double(y) + 0.5) / Double(height)
                depths[y * depthStride + x] = surface(CGPoint(x: 1 - sensorY, y: 1 - sensorX))
                confidences[y * confidenceStride + x] = confident ? 2 : 0
            }
        }
        CVPixelBufferUnlockBaseAddress(depthMap, [])
        CVPixelBufferUnlockBaseAddress(confidenceMap, [])
        return DepthFrame(depthMap: hasDepth ? depthMap : nil, confidenceMap: hasDepth ? confidenceMap : nil,
                          timestamp: time, intrinsics: intrinsics, imageResolution: resolution, isTrackingNormal: true)
    }

    /// A hand from Vision-coordinate joints (the tracker's input is top-left image coordinates).
    private func hand(_ joints: [HandJoint: CGPoint]) -> HandObservation {
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { joint, point in
            (joint, HandLandmark(joint: joint, location: CGPoint(x: point.x, y: 1 - point.y), confidence: 0.9))
        })
        return HandObservation(id: UUID(), chirality: .right, landmarks: landmarks, center: .zero, indexTip: nil,
                               pointingTip: nil, confidence: 0.9, state: .tracking, timestamp: 0, lastSeen: 0)
    }

    /// Two fingers pointing up into the middle of the object's box.
    private var handOverObject: HandObservation {
        hand([.indexTip: CGPoint(x: 0.5, y: 0.56), .indexDIP: CGPoint(x: 0.5, y: 0.52),
              .indexPIP: CGPoint(x: 0.5, y: 0.48), .indexMCP: CGPoint(x: 0.5, y: 0.44),
              .middleTip: CGPoint(x: 0.54, y: 0.56), .middleDIP: CGPoint(x: 0.54, y: 0.52),
              .middlePIP: CGPoint(x: 0.54, y: 0.48), .middleMCP: CGPoint(x: 0.54, y: 0.44),
              .wrist: CGPoint(x: 0.52, y: 0.36)])
    }

    private let handArea = CGRect(x: 0.47, y: 0.34, width: 0.10, height: 0.25)

    private func scene(handDepth: Float, handArea: CGRect? = nil) -> (CGPoint) -> Float {
        let area = handArea ?? self.handArea
        return { [box, objectDepth, wallDepth] point in
            if area.contains(point) { return handDepth }
            return box.contains(point) ? objectDepth : wallDepth
        }
    }

    private func run(_ tracker: LocateTracker, hands: [HandObservation], target: CGRect? = nil,
                     from start: TimeInterval = 1, frames: Int = 8,
                     frame: (TimeInterval) throws -> DepthFrame) rethrows {
        for index in 0..<frames {
            let time = start + Double(index) * 0.1
            tracker.update(depth: try frame(time), cameraTransform: matrix_identity_float4x4,
                           target: target ?? box, hands: hands)
        }
    }

    /// A spread hand whose padded joint box covers `rect` entirely.
    private func hand(covering rect: CGRect) -> HandObservation {
        let left = rect.minX + 0.04, right = rect.maxX - 0.04, bottom = rect.minY + 0.04, top = rect.maxY - 0.04
        let step = (top - bottom) / 3
        return hand([.indexTip: CGPoint(x: left, y: top), .indexDIP: CGPoint(x: left, y: top - step),
                     .indexPIP: CGPoint(x: left, y: top - 2 * step), .indexMCP: CGPoint(x: left, y: bottom),
                     .littleTip: CGPoint(x: right, y: top), .littleDIP: CGPoint(x: right, y: top - step),
                     .littlePIP: CGPoint(x: right, y: top - 2 * step), .littleMCP: CGPoint(x: right, y: bottom)])
    }

    /// The reported bug: fingertips overlap the object on screen while still 25 cm short of it.
    func testHandInFrontOfObjectIsNotContact() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [handOverObject]) { try depthFrame(at: $0, surface: scene(handDepth: 0.35)) }
        XCTAssertFalse(tracker.objectFound)
        XCTAssertFalse(tracker.approaching)
        let edge = try XCTUnwrap(tracker.leftHandEdge)
        XCTAssertTrue(edge.insideMask)
        XCTAssertEqual(try XCTUnwrap(edge.depthGap), 0.25, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(edge.distance), 0.25, accuracy: 0.02)
    }

    func testFingertipsAtTheObjectAreContact() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [handOverObject]) { try depthFrame(at: $0, surface: scene(handDepth: 0.59)) }
        XCTAssertTrue(tracker.objectFound)
        XCTAssertEqual(try XCTUnwrap(tracker.leftHandEdge?.depthGap), 0.01, accuracy: 0.02)
    }

    /// A hand covering the whole box leaves nothing of the object to read; its remembered position is used.
    func testHandCoveringTheWholeObjectUsesRememberedDepth() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [], frames: 1) { try depthFrame(at: $0, surface: scene(handDepth: 0.35, handArea: .null)) }
        let wideHand = hand([.indexTip: CGPoint(x: 0.4, y: 0.66), .indexDIP: CGPoint(x: 0.4, y: 0.6),
                             .indexPIP: CGPoint(x: 0.4, y: 0.5), .indexMCP: CGPoint(x: 0.4, y: 0.42),
                             .littleTip: CGPoint(x: 0.66, y: 0.62), .littleDIP: CGPoint(x: 0.64, y: 0.56),
                             .littlePIP: CGPoint(x: 0.62, y: 0.5), .littleMCP: CGPoint(x: 0.6, y: 0.42),
                             .thumbTip: CGPoint(x: 0.34, y: 0.5), .thumbIP: CGPoint(x: 0.36, y: 0.45),
                             .wrist: CGPoint(x: 0.5, y: 0.34)])
        try run(tracker, hands: [wideHand], from: 2) {
            try depthFrame(at: $0, surface: scene(handDepth: 0.35, handArea: box))
        }
        XCTAssertFalse(tracker.objectFound)
        XCTAssertEqual(try XCTUnwrap(tracker.leftHandEdge?.depthGap), 0.25, accuracy: 0.03)
    }

    /// Past the object's front with the hand over it: the remembered depth gives a negative gap, not the
    /// wall behind it read around the hand.
    func testOvershootWhileCoveringTheObjectReadsAsPast() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [], frames: 1) { try depthFrame(at: $0, surface: scene(handDepth: 0.7, handArea: .null)) }
        try run(tracker, hands: [handOverObject], from: 2, frames: 1) {
            try depthFrame(at: $0, surface: scene(handDepth: 0.7))
        }
        XCTAssertEqual(try XCTUnwrap(tracker.leftHandEdge?.depthGap), -0.1, accuracy: 0.02)
    }

    /// Switching to a different object must not measure against the first one's remembered position.
    func testSwitchingTargetsForgetsTheOldObject() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [], frames: 1) { try depthFrame(at: $0, surface: scene(handDepth: 0.35, handArea: .null)) }
        let other = CGRect(x: 0.05, y: 0.7, width: 0.24, height: 0.24)
        try run(tracker, hands: [hand(covering: other)], target: other, from: 2, frames: 1) { time in
            try depthFrame(at: time) { other.contains($0) ? 0.35 : 2.0 }
        }
        let edge = try XCTUnwrap(tracker.leftHandEdge)
        XCTAssertNil(edge.depthGap)
        XCTAssertEqual(edge.depthStatus, .objectUnreadable)
    }

    /// A closing grip hides the fingertips just as the hand arrives; contact still registers if depth
    /// showed the hand within reach of the object a moment before.
    func testGripAfterAMeasuredApproachIsContact() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [handOverObject], frames: 2) { try depthFrame(at: $0, surface: scene(handDepth: 0.52)) }
        XCTAssertFalse(tracker.objectFound)
        try run(tracker, hands: [handOverObject], from: 1.2, frames: 6) {
            try depthFrame(at: $0, confident: false, surface: scene(handDepth: 0.52))
        }
        XCTAssertTrue(tracker.objectFound)
    }

    func testDepthStatusSaysWhichSideIsMissing() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [handOverObject], frames: 1) {
            try depthFrame(at: $0, hasDepth: false, surface: scene(handDepth: 0.35))
        }
        XCTAssertEqual(tracker.leftHandEdge?.depthStatus, .noSensor)
        try run(tracker, hands: [handOverObject], from: 2, frames: 1) {
            try depthFrame(at: $0, confident: false, surface: scene(handDepth: 0.35))
        }
        XCTAssertEqual(tracker.leftHandEdge?.depthStatus, .handUnreadable)
        try run(tracker, hands: [handOverObject], from: 3, frames: 1) { try depthFrame(at: $0, surface: scene(handDepth: 0.35)) }
        XCTAssertEqual(tracker.leftHandEdge?.depthStatus, .measured)
    }

    /// With LiDAR, overlapping the object on screen is never contact by itself.
    func testUnreadableDepthDoesNotFallBackToScreenOverlap() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [handOverObject]) {
            try depthFrame(at: $0, confident: false, surface: scene(handDepth: 0.35))
        }
        XCTAssertFalse(tracker.objectFound)
        XCTAssertNil(tracker.leftHandEdge?.depthGap)
    }

    /// Without LiDAR there is nothing else to go on, so the screen-overlap stand-in still applies.
    func testPhonesWithoutDepthStillUseScreenOverlap() throws {
        let tracker = LocateTracker()
        try run(tracker, hands: [handOverObject]) {
            try depthFrame(at: $0, hasDepth: false, surface: scene(handDepth: 0.35))
        }
        XCTAssertTrue(tracker.objectFound)
    }
}

// MARK: - Spoken coaching

final class ReachCoachTests: XCTestCase {
    func testExplainsHandInFrontOnceThenGivesDistance() {
        var coach = ReachCoach()
        let first = coach.depthLine(gap: 0.25, status: .measured, handInFront: true, at: 10)
        XCTAssertEqual(first, .handInFront(inches: 10))
        coach.didSpeak(first!, at: 10)

        XCTAssertNil(coach.depthLine(gap: 0.25, status: .measured, handInFront: true, at: 11), "Too soon after the last line")
        XCTAssertNil(coach.depthLine(gap: 0.25, status: .measured, handInFront: true, at: 13), "Same advice, reminder not due")
        let reminder = coach.depthLine(gap: 0.25, status: .measured, handInFront: true, at: 15.5)
        XCTAssertEqual(reminder, .further(inches: 10), "Explained once; afterwards just the distance")
    }

    func testSignificantProgressIsSaidBeforeTheReminder() {
        var coach = ReachCoach()
        coach.didSpeak(.further(inches: 10), at: 10)
        XCTAssertEqual(coach.depthLine(gap: 0.1, status: .measured, handInFront: false, at: 13), .almost(inches: 4))
    }

    func testOvershootAndToleranceAndSmoothing() {
        var coach = ReachCoach()
        XCTAssertEqual(coach.depthLine(gap: -0.15, status: .measured, handInFront: true, at: 10), .overshot(inches: 6))
        var settled = ReachCoach()
        XCTAssertNil(settled.depthLine(gap: 0.04, status: .measured, handInFront: false, at: 10), "Inside tolerance: step one is done")
        // One wild reading among steady ones is outvoted by the median.
        var smoothed = ReachCoach()
        _ = smoothed.depthLine(gap: 0.2, status: .measured, handInFront: false, at: 10)
        _ = smoothed.depthLine(gap: 0.2, status: .measured, handInFront: false, at: 10.1)
        XCTAssertEqual(smoothed.depthLine(gap: -0.5, status: .measured, handInFront: false, at: 10.2), .further(inches: 8))
    }

    func testAsksForOpenHandOnlyAfterDepthIsMissingForAWhile() {
        var coach = ReachCoach()
        XCTAssertNil(coach.depthLine(gap: nil, status: .handUnreadable, handInFront: false, at: 10))
        XCTAssertNil(coach.depthLine(gap: nil, status: .handUnreadable, handInFront: false, at: 12))
        XCTAssertEqual(coach.depthLine(gap: nil, status: .handUnreadable, handInFront: false, at: 14), .showFingers)
    }

    func testSilentWithoutADepthSensor() {
        var coach = ReachCoach()
        for time in stride(from: 10.0, through: 30, by: 1) {
            XCTAssertNil(coach.depthLine(gap: nil, status: .noSensor, handInFront: true, at: time))
        }
    }

    func testAsksToUncoverTheObjectWhenOnlyItsDepthIsMissing() {
        var coach = ReachCoach()
        XCTAssertNil(coach.depthLine(gap: nil, status: .objectUnreadable, handInFront: true, at: 10))
        XCTAssertEqual(coach.depthLine(gap: nil, status: .objectUnreadable, handInFront: true, at: 14), .revealObject)
        XCTAssertEqual(ReachCoach.text(for: .revealObject, objectName: "bottle"),
                       "Move your hand aside for a moment, so I can see the bottle.")
    }

    func testOtherSpeechDelaysTheNextLine() {
        var coach = ReachCoach()
        coach.noteSpeech(at: 10)
        XCTAssertNil(coach.depthLine(gap: 0.3, status: .measured, handInFront: false, at: 11))
        XCTAssertNotNil(coach.depthLine(gap: 0.3, status: .measured, handInFront: false, at: 12.6))
    }

    func testStepChangeHoldsTheNextLine() {
        var coach = ReachCoach()
        coach.stepChanged(at: 10)
        XCTAssertNil(coach.depthLine(gap: 0.3, status: .measured, handInFront: false, at: 11))
        XCTAssertNotNil(coach.depthLine(gap: 0.3, status: .measured, handInFront: false, at: 12.6))
    }

    func testLateralDirection() {
        let coach = ReachCoach()
        XCTAssertEqual(coach.lateralLine(dx: 0.2, tolerance: 0.05, at: 10), .lateral(towardRight: true))
        XCTAssertEqual(coach.lateralLine(dx: -0.2, tolerance: 0.05, at: 10), .lateral(towardRight: false))
        XCTAssertNil(coach.lateralLine(dx: 0.02, tolerance: 0.05, at: 10))
    }

    func testDistanceWording() {
        XCTAssertEqual(ReachCoach.inches(0.01), 2)
        XCTAssertEqual(ReachCoach.distance(10), "10 inches")
        XCTAssertEqual(ReachCoach.distance(14), "a foot")
        XCTAssertEqual(ReachCoach.distance(24), "2 feet")
        XCTAssertEqual(ReachCoach.text(for: .handInFront(inches: 10), objectName: "bottle"),
                       "Your hand is in front of the bottle, not at it yet. Reach about 10 inches further.")
    }

    /// `VoiceListener` hears the speaker; any of Locate's back keywords would leave the screen.
    func testNoLineContainsAGoBackKeyword() {
        let keywords = ["back", "return", "previous", "exit", "leave", "quit", "cancel"]
        let lines: [ReachCoach.Line] = [.handInFront(inches: 10), .further(inches: 20), .almost(inches: 2),
                                        .overshot(inches: 6), .showFingers, .revealObject, .lateral(towardRight: true),
                                        .lateral(towardRight: false)]
        for line in lines {
            let words = ReachCoach.text(for: line, objectName: "bottle").lowercased()
                .split { !$0.isLetter && $0 != "'" }.map(String.init)
            for keyword in keywords {
                XCTAssertFalse(words.contains(keyword), "\"\(keyword)\" in \(line)")
            }
        }
    }
}
