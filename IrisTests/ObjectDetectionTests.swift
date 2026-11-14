import XCTest
import CoreML
import CoreVideo
@testable import Iris

final class ObjectDetectionTests: XCTestCase {
    private let size = CGSize(width: 1440, height: 1920)
    private let box = CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.3)

    private func candidate(_ name: String = "cup", x: CGFloat = 0.2, confidence: Double = 0.9) -> ObjectCandidate {
        .init(name: name, confidence: confidence, boundingBox: CGRect(x: x, y: 0.3, width: 0.2, height: 0.3))
    }

    func testSelectionFollowsMatchedObjectAndNewBounds() throws {
        var state = ObjectDetectionState()
        state.update([candidate()], timestamp: 1, imageSize: size)
        let id = try XCTUnwrap(state.snapshot.objects.first?.id)
        state.select(id)
        state.update([candidate(x: 0.22)], timestamp: 1.2, imageSize: size)
        XCTAssertEqual(state.snapshot.objects.first?.id, id)
        XCTAssertEqual(state.snapshot.selectedTarget?.currentBoundingBox?.minX, 0.22)
        XCTAssertEqual(state.snapshot.selectedTarget?.lastSeenTimestamp, 1.2)
        XCTAssertEqual(state.snapshot.selectedTarget?.state, .tracking)
    }

    func testEmptyResultsLoseTargetAndBriefReappearanceReusesID() throws {
        var state = ObjectDetectionState()
        state.update([candidate()], timestamp: 1, imageSize: size)
        let id = try XCTUnwrap(state.snapshot.objects.first?.id)
        state.select(id)
        state.update([], timestamp: 1.2, imageSize: size)
        XCTAssertTrue(state.snapshot.objects.isEmpty)
        XCTAssertEqual(state.snapshot.selectedTarget?.state, .lost)
        XCTAssertNil(state.snapshot.selectedTarget?.currentBoundingBox)
        XCTAssertNil(state.snapshot.selectedTarget?.sensorBoundingBox)
        state.update([candidate()], timestamp: 1.4, imageSize: size)
        XCTAssertEqual(state.snapshot.objects.first?.id, id)
        XCTAssertEqual(state.snapshot.selectedTarget?.state, .tracking)
    }

    func testExpiredIdentityNeverAutomaticallySelectsReplacement() throws {
        var state = ObjectDetectionState()
        state.update([candidate()], timestamp: 1, imageSize: size)
        let id = try XCTUnwrap(state.snapshot.objects.first?.id)
        state.select(id)
        state.expire(at: 2)
        XCTAssertTrue(state.snapshot.objects.isEmpty)
        XCTAssertNil(state.snapshot.selectedTarget?.currentBoundingBox)
        state.update([candidate()], timestamp: 2.1, imageSize: size)
        XCTAssertNotEqual(state.snapshot.objects.first?.id, id)
        XCTAssertEqual(state.snapshot.selectedTarget?.object.id, id)
        XCTAssertEqual(state.snapshot.selectedTarget?.state, .lost)
    }

    func testAssociationIsOneToOneAndClassSpecific() {
        var state = ObjectDetectionState()
        state.update([candidate(), candidate(x: 0.6)], timestamp: 1, imageSize: size)
        let ids = state.snapshot.objects.map(\.id)
        state.update([candidate(x: 0.61), candidate(x: 0.21)], timestamp: 1.2, imageSize: size)
        XCTAssertEqual(state.snapshot.objects.map(\.id), ids)
        state.update([candidate("bottle", x: 0.21), candidate(x: 0.61)], timestamp: 1.4, imageSize: size)
        XCTAssertFalse(state.snapshot.objects.contains { $0.id == ids[0] })
        XCTAssertEqual(Set(state.snapshot.objects.map(\.id)).count, 2)
    }

    func testInvalidSelectionClearAndSuspend() throws {
        var state = ObjectDetectionState()
        state.update([candidate()], timestamp: 1, imageSize: size)
        state.select(UUID())
        XCTAssertNil(state.snapshot.selectedTarget)
        let id = try XCTUnwrap(state.snapshot.objects.first?.id)
        state.select(id)
        state.suspend()
        XCTAssertTrue(state.snapshot.objects.isEmpty)
        XCTAssertNil(state.snapshot.timestamp)
        XCTAssertEqual(state.snapshot.selectedTarget?.state, .lost)
        state.clearSelection()
        XCTAssertNil(state.snapshot.selectedTarget)
    }

    func testOutOfOrderResultsAndInvalidCandidatesAreRejected() {
        var state = ObjectDetectionState()
        state.update([candidate(), candidate(confidence: .nan), candidate(confidence: 0.2),
                      candidate("", x: 0.5), candidate(x: 2)], timestamp: 2, imageSize: size)
        XCTAssertEqual(state.snapshot.objects.count, 1)
        let original = state.snapshot
        state.update([], timestamp: 1, imageSize: size)
        XCTAssertEqual(state.snapshot, original)
    }

    func testVisionYFlipWithoutCropping() {
        let rect = DetectionGeometry.viewRect(box, imageSize: size, viewport: CGSize(width: 300, height: 400))
        assertRect(rect, CGRect(x: 60, y: 160, width: 60, height: 120))
    }

    func testTallViewportCropsHorizontalEdges() {
        let rect = DetectionGeometry.viewRect(CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: CGSize(width: 300, height: 400), viewport: CGSize(width: 300, height: 600))
        assertRect(rect, CGRect(x: -75, y: 0, width: 450, height: 600))
    }

    func testWideViewportCropsVerticalEdgesAndResizes() {
        let rect = DetectionGeometry.viewRect(CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: CGSize(width: 300, height: 400), viewport: CGSize(width: 600, height: 400))
        assertRect(rect, CGRect(x: 0, y: -200, width: 600, height: 800))
        XCTAssertEqual(DetectionGeometry.viewRect(box, imageSize: .zero, viewport: size), .zero)
    }

    func testPortraitToNativeSensorRotation() {
        assertRect(DetectionGeometry.sensorRect(box), CGRect(x: 0.4, y: 0.6, width: 0.3, height: 0.2))
    }

    func testClippingRejectsInvalidBounds() throws {
        assertRect(try XCTUnwrap(DetectionGeometry.clippedUnitRect(CGRect(x: -0.1, y: 0.9, width: 0.3, height: 0.4))),
                   CGRect(x: 0, y: 0.9, width: 0.2, height: 0.1))
        XCTAssertNil(DetectionGeometry.clippedUnitRect(CGRect(x: 2, y: 0, width: 1, height: 1)))
        XCTAssertNil(DetectionGeometry.clippedUnitRect(CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1)))
        XCTAssertNil(DetectionGeometry.clippedUnitRect(.zero))
    }

    func testMissingModelReportsFailure() async {
        do {
            try await VisionObjectDetector().prepare(modelURL: nil)
            XCTFail("Expected a missing-model error")
        } catch {
            XCTAssertTrue(error is ObjectDetectionError)
        }
    }

    func testBundledModelSchemaAndRealVisionInference() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "YOLOv3TinyFP16", withExtension: "mlmodelc"))
        let model = try MLModel(contentsOf: url)
        let labels = try XCTUnwrap(model.modelDescription.classLabels as? [String])
        XCTAssertEqual(labels.count, 80)
        XCTAssertTrue(["cup", "bottle", "chair", "book"].allSatisfy(labels.contains))
        let detector = VisionObjectDetector()
        try await detector.prepare(modelURL: url)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let image = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(image, [])
        memset(CVPixelBufferGetBaseAddress(image), 0, CVPixelBufferGetDataSize(image))
        CVPixelBufferUnlockBaseAddress(image, [])
        let results = try await detector.detect(image)
        XCTAssertTrue(results.allSatisfy { labels.contains($0.name) && $0.confidence >= 0.35 })
    }

    @MainActor
    func testStoppingDuringModelLoadCannotRestoreReadyState() async throws {
        let service = ObjectDetectionService()
        let stream = AsyncStream<CameraFrame> { _ in }
        service.start(frames: stream)
        service.stop()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(service.readiness, .planned)
        XCTAssertTrue(service.latestObjects.isEmpty)
        XCTAssertNil(service.selectedTarget)
    }

    private func assertRect(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.00001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.00001, file: file, line: line)
    }
}
