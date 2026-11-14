import XCTest
import CoreVideo
import simd
@testable import Iris

final class DepthEstimationTests: XCTestCase {
    private let objectID = UUID()
    private let resolution = CGSize(width: 400, height: 300)
    private let intrinsics = simd_float3x3(columns: (SIMD3(200, 0, 0), SIMD3(0, 200, 0), SIMD3(200, 150, 1)))

    private func target(at time: Double = 1, id: UUID? = nil, state: ObjectTrackingState = .tracking,
                        box: CGRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)) -> SelectedObjectTarget {
        .init(object: .init(id: id ?? objectID, name: "bottle", confidence: 0.9, boundingBox: box),
              state: state, lastSeenTimestamp: time, uprightImageSize: CGSize(width: 300, height: 400))
    }

    private func frame(at time: Double = 1, tracking: Bool = true, hasDepth: Bool = true,
                       hasConfidence: Bool = true, width: Int = 40, height: Int = 30,
                       value: (Int, Int) -> Float = { _, _ in 1 },
                       confidence: (Int, Int) -> UInt8 = { _, _ in 2 }) throws -> DepthFrame {
        var depth: CVPixelBuffer?
        var levels: CVPixelBuffer?
        let attributes = [kCVPixelBufferBytesPerRowAlignmentKey: 128] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DepthFloat32,
                                           attributes, &depth), kCVReturnSuccess)
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8,
                                           attributes, &levels), kCVReturnSuccess)
        let depthMap = try XCTUnwrap(depth), confidenceMap = try XCTUnwrap(levels)
        CVPixelBufferLockBaseAddress(depthMap, [])
        CVPixelBufferLockBaseAddress(confidenceMap, [])
        let depthBase = try XCTUnwrap(CVPixelBufferGetBaseAddress(depthMap)).assumingMemoryBound(to: Float.self)
        let confidenceBase = try XCTUnwrap(CVPixelBufferGetBaseAddress(confidenceMap)).assumingMemoryBound(to: UInt8.self)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float>.stride
        let confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
        // Padding deliberately differs from image values, catching incorrect packed-row indexing.
        depthBase.initialize(repeating: .nan, count: depthStride * height)
        confidenceBase.initialize(repeating: 0, count: confidenceStride * height)
        for y in 0..<height {
            for x in 0..<width {
                depthBase[y * depthStride + x] = value(x, y)
                confidenceBase[y * confidenceStride + x] = confidence(x, y)
            }
        }
        CVPixelBufferUnlockBaseAddress(depthMap, [])
        CVPixelBufferUnlockBaseAddress(confidenceMap, [])
        return .init(depthMap: hasDepth ? depthMap : nil, confidenceMap: hasConfidence ? confidenceMap : nil,
                     timestamp: time, intrinsics: intrinsics, imageResolution: resolution, isTrackingNormal: tracking)
    }

    func testVisionPortraitBoxMapsToCorrectNativeDepthRegion() throws {
        let target = target(box: CGRect(x: 0.65, y: 0.65, width: 0.2, height: 0.2))
        let region = try XCTUnwrap(DepthGeometry.sensorRegion(for: target, imageResolution: resolution))
        XCTAssertEqual(region.minX, 0.15, accuracy: 0.0001)
        XCTAssertEqual(region.minY, 0.15, accuracy: 0.0001)
        let depth = try frame(value: { x, y in x < 16 && y < 12 ? 0.7 : 3 })
        guard case let .measured(meters) = DepthSampler.sample(frame: depth, sensorRegion: region) else {
            return XCTFail("Expected the top-left sensor region, not background")
        }
        XCTAssertEqual(meters, 0.7, accuracy: 0.0001)
        XCTAssertNil(DepthGeometry.sensorRegion(for: target, imageResolution: CGSize(width: 300, height: 400)))
    }

    func testIntrinsicsProduceCameraBearingAndRadialDistance() throws {
        let frame = try frame()
        let ray = try XCTUnwrap(DepthGeometry.portraitRay(sensorPoint: CGPoint(x: 0.25, y: 0.25), frame: frame))
        XCTAssertEqual(ray, SIMD3(0.375, 0.5, 1))
        let estimate = DepthGeometry.estimate(objectID: objectID, ray: ray, axialDepth: 2,
                                              validity: .measured, timestamp: 1)
        XCTAssertEqual(estimate.horizontalPosition, .right)
        XCTAssertEqual(estimate.verticalPosition, .above)
        XCTAssertEqual(estimate.positionInPortraitCameraMeters, SIMD3(0.75, 1, 2))
        XCTAssertEqual(try XCTUnwrap(estimate.distanceMeters), sqrt(5.5625), accuracy: 0.0001)
        XCTAssertEqual(estimate.timestamp, 1)
    }

    func testDirectionSignsAndCenterDeadBand() throws {
        let frame = try frame()
        for (point, horizontal, vertical) in [
            (CGPoint(x: 0.5, y: 0.5), HorizontalPosition.center, VerticalPosition.center),
            (CGPoint(x: 0.75, y: 0.75), .left, .below),
            (CGPoint(x: 0.25, y: 0.75), .left, .above),
            (CGPoint(x: 0.75, y: 0.25), .right, .below)
        ] {
            let ray = try XCTUnwrap(DepthGeometry.portraitRay(sensorPoint: point, frame: frame))
            let estimate = DepthGeometry.estimate(objectID: objectID, ray: ray, axialDepth: nil,
                                                  validity: .unavailable(.missingDepth), timestamp: 1)
            XCTAssertEqual(estimate.horizontalPosition, horizontal)
            XCTAssertEqual(estimate.verticalPosition, vertical)
            XCTAssertNil(estimate.distanceMeters)
            XCTAssertNil(estimate.positionInPortraitCameraMeters)
        }
    }

    func testInvalidIntrinsicsCannotProduceDistance() throws {
        let original = try frame()
        let invalid = DepthFrame(depthMap: original.depthMap, confidenceMap: original.confidenceMap,
            timestamp: 1, intrinsics: simd_float3x3(), imageResolution: resolution, isTrackingNormal: true)
        var processor = DepthEstimationProcessor()
        XCTAssertEqual(processor.process(invalid, target: target(), supportsSceneDepth: true)?.validity,
                       .unavailable(.invalidGeometry))
    }

    func testMedianRejectsOutliersAndHonorsRowStrides() throws {
        let frame = try frame(width: 23, height: 19, value: { x, _ in x % 8 == 0 ? 4 : 0.7 })
        guard case let .measured(depth) = DepthSampler.sample(frame: frame, sensorRegion: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return XCTFail("Expected robust median")
        }
        XCTAssertEqual(depth, 0.7, accuracy: 0.0001)
    }

    func testNonFiniteNonPositiveAndOutOfRangeSamplesAreUnavailable() throws {
        for value: Float in [.nan, .infinity, 0, -1, 0.1, 6] {
            let frame = try frame(value: { _, _ in value })
            assertUnavailable(DepthSampler.sample(frame: frame, sensorRegion: CGRect(x: 0, y: 0, width: 1, height: 1)), .lowConfidence)
        }
    }

    func testLowAndMissingConfidenceAreUnavailable() throws {
        for frame in [try frame(confidence: { _, _ in 0 }), try frame(hasConfidence: false),
                      try frame(confidence: { x, _ in x % 8 == 0 ? 2 : 0 })] {
            assertUnavailable(DepthSampler.sample(frame: frame, sensorRegion: CGRect(x: 0, y: 0, width: 1, height: 1)), .lowConfidence)
        }
    }

    func testMediumConfidenceSamplesCanBeMeasured() throws {
        let frame = try frame(confidence: { _, _ in 1 })
        guard case let .measured(depth) = DepthSampler.sample(frame: frame, sensorRegion: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return XCTFail("Expected valid medium-confidence samples")
        }
        XCTAssertEqual(depth, 1)
    }

    func testMixedSurfacesAreRejected() throws {
        let frame = try frame(value: { x, _ in x < 20 ? 0.7 : 2 })
        assertUnavailable(DepthSampler.sample(frame: frame, sensorRegion: CGRect(x: 0, y: 0, width: 1, height: 1)), .inconsistentDepth)
    }

    func testTinyBoxDoesNotExpandIntoBackground() throws {
        let frame = try frame()
        assertUnavailable(DepthSampler.sample(frame: frame, sensorRegion: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01)), .lowConfidence)
    }

    func testDelayedDetectionUsesItsOwnDepthFrame() throws {
        var processor = DepthEstimationProcessor()
        _ = processor.process(try frame(at: 1, value: { _, _ in 0.7 }), target: nil, supportsSceneDepth: true)
        let estimate = try XCTUnwrap(processor.process(try frame(at: 1.2, value: { _, _ in 3 }),
                                                      target: target(at: 1), supportsSceneDepth: true))
        XCTAssertEqual(try XCTUnwrap(estimate.distanceMeters), 0.7, accuracy: 0.0001)
        XCTAssertEqual(estimate.timestamp, 1)
    }

    func testNoMatchedFrameNeverSubstitutesLatestDepth() throws {
        var processor = DepthEstimationProcessor()
        let estimate = processor.process(try frame(at: 1.2), target: target(at: 1), supportsSceneDepth: true)
        XCTAssertEqual(estimate?.validity, .unavailable(.unmatchedFrame))
        XCTAssertNil(estimate?.distanceMeters)
    }

    func testHistoryIsBoundedAndOldObservationsExpire() throws {
        var processor = DepthEstimationProcessor()
        let original = try frame()
        for index in 0..<120 {
            let frame = DepthFrame(depthMap: original.depthMap, confidenceMap: original.confidenceMap,
                timestamp: 1 + Double(index) / 120, intrinsics: intrinsics,
                imageResolution: resolution, isTrackingNormal: true)
            _ = processor.process(frame, target: nil, supportsSceneDepth: true)
        }
        XCTAssertLessThanOrEqual(processor.frames.count, DepthEstimationProcessor.historyLimit)
        let estimate = processor.process(try frame(at: 2.1), target: target(at: 1), supportsSceneDepth: true)
        XCTAssertEqual(estimate?.validity, .unavailable(.staleObservation))
        XCTAssertNil(estimate?.distanceMeters)
    }

    func testLostTargetAndTrackingInterruptionInvalidateMeasurements() throws {
        var processor = DepthEstimationProcessor()
        XCTAssertEqual(processor.process(try frame(), target: target(), supportsSceneDepth: true)?.validity, .measured)
        let lost = processor.process(try frame(at: 1.1), target: target(state: .lost), supportsSceneDepth: true)
        XCTAssertEqual(lost?.validity, .unavailable(.targetLost))
        XCTAssertNil(lost?.distanceMeters)
        let interrupted = processor.process(try frame(at: 1.2, tracking: false), target: target(), supportsSceneDepth: true)
        XCTAssertEqual(interrupted?.validity, .unavailable(.trackingLimited))
        XCTAssertTrue(processor.frames.isEmpty)
        let recovered = processor.process(try frame(at: 1.3), target: target(), supportsSceneDepth: true)
        XCTAssertEqual(recovered?.validity, .unavailable(.unmatchedFrame))
    }

    func testMissingDepthImmediatelyClearsPreviousMeasurement() throws {
        var processor = DepthEstimationProcessor()
        _ = processor.process(try frame(), target: target(), supportsSceneDepth: true)
        let missing = processor.process(try frame(at: 1.1, hasDepth: false), target: target(), supportsSceneDepth: true)
        XCTAssertEqual(missing?.validity, .unavailable(.missingDepth))
        XCTAssertNil(missing?.distanceMeters)
    }

    func testUnsupportedDeviceHasOnlyBearingWithoutInventedMeters() throws {
        var processor = DepthEstimationProcessor()
        let estimate = processor.process(try frame(hasDepth: false), target: target(), supportsSceneDepth: false)
        XCTAssertEqual(estimate?.validity, .unavailable(.unsupportedDevice))
        XCTAssertEqual(estimate?.horizontalPosition, .center)
        XCTAssertNil(estimate?.distanceMeters)
        XCTAssertNil(estimate?.positionInPortraitCameraMeters)
    }

    func testSmoothingResetsForNewTargetGapsAndLargeJumps() {
        var smoother = DepthSmoother()
        XCTAssertEqual(smoother.update(1, objectID: objectID, timestamp: 1), 1)
        let smoothed = smoother.update(1.1, objectID: objectID, timestamp: 1.1)
        XCTAssertGreaterThan(smoothed, 1)
        XCTAssertLessThan(smoothed, 1.1)
        XCTAssertEqual(smoother.update(1.2, objectID: UUID(), timestamp: 1.2), 1.2)
        XCTAssertEqual(smoother.update(1.3, objectID: objectID, timestamp: 2), 1.3)
        XCTAssertEqual(smoother.update(3, objectID: objectID, timestamp: 2.1), 3)
        smoother.reset()
        XCTAssertEqual(smoother.update(3.1, objectID: objectID, timestamp: 2.2), 3.1)
    }

    @MainActor
    func testServiceSelectionStopAndRestartFallbacks() async {
        let service = DepthEstimationService()
        let stream = AsyncStream<CameraFrame> { _ in }
        service.start(frames: stream, supportsSceneDepth: false)
        service.setTarget(target())
        XCTAssertEqual(service.estimate?.validity, .unavailable(.unsupportedDevice))
        service.stop()
        XCTAssertEqual(service.estimate?.validity, .unavailable(.cameraPaused))
        service.start(frames: AsyncStream<CameraFrame> { _ in }, supportsSceneDepth: true)
        XCTAssertEqual(service.estimate?.validity, .unavailable(.waitingForDepth))
        service.setTarget(target(state: .lost))
        XCTAssertEqual(service.estimate?.validity, .unavailable(.targetLost))
        service.setTarget(nil)
        XCTAssertNil(service.estimate)
        service.stop()
    }

    private func assertUnavailable(_ result: DepthSampleResult, _ expected: DepthUnavailableReason,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard case let .unavailable(reason) = result else {
            return XCTFail("Expected unavailable distance", file: file, line: line)
        }
        XCTAssertEqual(reason, expected, file: file, line: line)
    }
}
