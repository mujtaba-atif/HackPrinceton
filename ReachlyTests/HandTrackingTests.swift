import XCTest
@testable import Reachly

final class HandTrackingTests: XCTestCase {
    private let imageSize = CGSize(width: 1440, height: 1920)

    private func pose(dx: CGFloat = 0, dy: CGFloat = 0, chirality: HandChirality = .right,
                      confidence: Double = 0.9, joints: [HandJoint] = HandJoint.allCases) -> RawHandPose {
        let base = HandTrackingSnapshot.preview.hands[0].landmarks
        var landmarks: [HandJoint: HandLandmark] = [:]
        for joint in joints {
            guard let point = base[joint]?.location else { continue }
            landmarks[joint] = HandLandmark(joint: joint, location: CGPoint(x: point.x + dx, y: point.y + dy),
                                            confidence: confidence)
        }
        return RawHandPose(chirality: chirality, landmarks: landmarks)
    }

    // MARK: Geometry

    func testImageViewRoundTripWithAspectFill() throws {
        let viewport = CGSize(width: 390, height: 844) // taller than 3:4, so the sides are cropped
        for mirrored in [false, true] {
            let point = CGPoint(x: 0.3, y: 0.7)
            let view = HandGeometry.imageToView(point, imageSize: imageSize, viewport: viewport, mirrored: mirrored)
            let back = try XCTUnwrap(HandGeometry.viewToImage(view, imageSize: imageSize, viewport: viewport, mirrored: mirrored))
            XCTAssertEqual(back.x, point.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, point.y, accuracy: 1e-9)
        }
        let center = HandGeometry.imageToView(CGPoint(x: 0.5, y: 0.5), imageSize: imageSize, viewport: viewport)
        XCTAssertEqual(center.x, 195, accuracy: 1e-9)
        XCTAssertEqual(center.y, 422, accuracy: 1e-9)
        // Height fills; width overflows symmetrically.
        let topLeft = HandGeometry.imageToView(.zero, imageSize: imageSize, viewport: viewport)
        XCTAssertEqual(topLeft.y, 0, accuracy: 1e-9)
        XCTAssertLessThan(topLeft.x, 0)
    }

    func testMirroringFlipsHorizontally() {
        let viewport = CGSize(width: 300, height: 400)
        let a = HandGeometry.imageToView(CGPoint(x: 0.2, y: 0.5), imageSize: imageSize, viewport: viewport)
        let b = HandGeometry.imageToView(CGPoint(x: 0.2, y: 0.5), imageSize: imageSize, viewport: viewport, mirrored: true)
        XCTAssertEqual(a.x, 60, accuracy: 1e-9)
        XCTAssertEqual(b.x, 240, accuracy: 1e-9)
        XCTAssertEqual(HandChirality.left.mirrored, .right)
    }

    func testVisionAndSensorConversions() {
        let image = HandGeometry.visionToImage(CGPoint(x: 0.2, y: 0.9))
        XCTAssertEqual(image.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(image.y, 0.1, accuracy: 1e-9)
        // Upright top-left corner maps to the landscape sensor's bottom-left corner under `.right`.
        XCTAssertEqual(HandGeometry.imageToSensor(CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 1))
        XCTAssertEqual(HandGeometry.uprightSize(forBufferSize: CGSize(width: 1920, height: 1440)), imageSize)
    }

    func testConvexHullExcludesInteriorPoints() {
        let hull = HandGeometry.convexHull([.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1),
                                            CGPoint(x: 0, y: 1), CGPoint(x: 0.5, y: 0.5)])
        XCTAssertEqual(hull.count, 4)
        XCTAssertFalse(hull.contains(CGPoint(x: 0.5, y: 0.5)))
    }

    // MARK: Filter

    func testOneEuroReducesJitterAndConverges() {
        var filter = OneEuroFilter()
        var outputs: [Double] = []
        for frame in 0..<60 {
            let noisy = 0.5 + (frame.isMultiple(of: 2) ? 0.01 : -0.01)
            outputs.append(filter.filter(noisy, timestamp: Double(frame) / 15))
        }
        let tail = outputs.suffix(20)
        XCTAssertLessThan(tail.max()! - tail.min()!, 0.02 * 0.5)
        XCTAssertEqual(tail.last!, 0.5, accuracy: 0.01)

        var step = OneEuroFilter()
        _ = step.filter(0, timestamp: 0)
        var value = 0.0
        for frame in 1...30 { value = step.filter(1, timestamp: Double(frame) / 15) }
        XCTAssertEqual(value, 1, accuracy: 0.02)
    }

    // MARK: Reducer

    func testStableIdentityAcrossFrames() throws {
        var reducer = HandTrackingReducer()
        reducer.update([pose()], timestamp: 1, imageSize: imageSize)
        let id = try XCTUnwrap(reducer.snapshot.hands.first?.id)
        reducer.update([pose(dx: 0.03)], timestamp: 1.07, imageSize: imageSize)
        XCTAssertEqual(reducer.snapshot.hands.first?.id, id)
        XCTAssertEqual(reducer.snapshot.primaryHand?.state, .tracking)
        XCTAssertEqual(reducer.snapshot.overallState, .tracking)
        let tip = try XCTUnwrap(reducer.snapshot.primaryHand?.pointingTip)
        // Smoothed: between the old (0.40) and new (0.43) index tip x.
        XCTAssertGreaterThan(tip.x, 0.40)
        XCTAssertLessThan(tip.x, 0.43)
    }

    func testFarJumpCreatesNewTrack() throws {
        var reducer = HandTrackingReducer()
        reducer.update([pose()], timestamp: 1, imageSize: imageSize)
        let id = try XCTUnwrap(reducer.snapshot.hands.first?.id)
        reducer.update([pose(dx: 0.35)], timestamp: 1.07, imageSize: imageSize)
        XCTAssertTrue(reducer.snapshot.hands.contains { $0.id != id && $0.state == .tracking })
        XCTAssertEqual(reducer.snapshot.hands.first { $0.id == id }?.state, .lost)
    }

    func testLowConfidenceOrFewJointsIsLimited() {
        var reducer = HandTrackingReducer()
        reducer.update([pose(confidence: 0.35)], timestamp: 1, imageSize: imageSize)
        XCTAssertEqual(reducer.snapshot.primaryHand?.state, .limited)

        var sparse = HandTrackingReducer()
        sparse.update([pose(joints: [.wrist, .indexMCP, .indexTip])], timestamp: 1, imageSize: imageSize)
        XCTAssertEqual(sparse.snapshot.primaryHand?.state, .limited)
    }

    func testMissingHandCoastsThenDropsAndReacquires() throws {
        var reducer = HandTrackingReducer()
        reducer.update([pose()], timestamp: 1, imageSize: imageSize)
        let id = try XCTUnwrap(reducer.snapshot.hands.first?.id)

        reducer.update([], timestamp: 1.2, imageSize: imageSize)
        XCTAssertEqual(reducer.snapshot.hands.first?.state, .lost)
        XCTAssertEqual(reducer.snapshot.hands.first?.id, id)

        reducer.update([pose()], timestamp: 1.3, imageSize: imageSize)
        XCTAssertEqual(reducer.snapshot.hands.first?.id, id, "Brief dropout keeps identity")
        XCTAssertEqual(reducer.snapshot.hands.first?.state, .tracking)

        reducer.update([], timestamp: 1.8, imageSize: imageSize)
        XCTAssertTrue(reducer.snapshot.hands.isEmpty)
        XCTAssertEqual(reducer.snapshot.overallState, .searching)
    }

    func testWatchdogExpiresStaleHands() {
        var reducer = HandTrackingReducer()
        reducer.update([pose()], timestamp: 1, imageSize: imageSize)
        reducer.expire(at: 1.3)
        XCTAssertEqual(reducer.snapshot.hands.first?.state, .lost)
        reducer.expire(at: 1.5)
        XCTAssertTrue(reducer.snapshot.hands.isEmpty)
    }

    func testFingertipFallsBackToDistalJoint() throws {
        var reducer = HandTrackingReducer()
        let joints = HandJoint.allCases.filter { $0 != .indexTip && $0 != .indexDIP }
        reducer.update([pose(joints: joints)], timestamp: 1, imageSize: imageSize)
        let hand = try XCTUnwrap(reducer.snapshot.primaryHand)
        let pip = try XCTUnwrap(HandTrackingSnapshot.preview.hands[0].landmarks[.indexPIP]?.location)
        XCTAssertEqual(hand.indexTip, pip)
        XCTAssertEqual(hand.pointingTip, pip)
    }

    func testCenterFallsBackWithoutMiddleKnuckle() throws {
        let landmarks = pose(joints: [.wrist, .indexMCP, .ringMCP]).landmarks
        let center = try XCTUnwrap(HandTrackingReducer.center(of: landmarks))
        XCTAssertEqual(center.x, (0.50 + 0.44 + 0.56) / 3, accuracy: 1e-9)
    }

    func testSuspendClearsAndRejectsOutOfOrderFrames() {
        var reducer = HandTrackingReducer()
        reducer.update([pose()], timestamp: 2, imageSize: imageSize)
        reducer.update([pose(dx: 0.1)], timestamp: 1.5, imageSize: imageSize)
        XCTAssertEqual(reducer.snapshot.timestamp, 2)

        reducer.suspend()
        XCTAssertTrue(reducer.snapshot.hands.isEmpty)
        XCTAssertEqual(reducer.snapshot.overallState, .suspended)
        reducer.resume()
        XCTAssertEqual(reducer.snapshot.overallState, .searching)
    }
}
