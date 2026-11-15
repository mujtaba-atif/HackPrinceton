import XCTest
@testable import Iris

final class VoiceAssistantTests: XCTestCase {

    // MARK: Command parsing

    func testSampleCommandsParse() {
        XCTAssertEqual(VoiceCommandParser.parse("What am I looking at?"), .identify)
        XCTAssertEqual(VoiceCommandParser.parse("Read this label"), .readText)
        XCTAssertEqual(VoiceCommandParser.parse("What does this say?"), .readText)
        XCTAssertEqual(VoiceCommandParser.parse("Find my water bottle"), .find("water bottle"))
        XCTAssertEqual(VoiceCommandParser.parse("What objects are nearby?"), .listObjects)
        XCTAssertEqual(VoiceCommandParser.parse("Stop speaking"), .stopSpeaking)
    }

    func testFindVariantsStripFiller() {
        XCTAssertEqual(VoiceCommandParser.parse("Can you help me find the keys please"), .find("keys"))
        XCTAssertEqual(VoiceCommandParser.parse("Where’s my phone?"), .find("phone"))
        XCTAssertEqual(VoiceCommandParser.parse("Hey Iris, I'm looking for a cup"), .find("cup"))
    }

    func testOpenQuestionsBecomeAsk() {
        XCTAssertEqual(VoiceCommandParser.parse("Can you summarize these instructions?"),
                       .ask("Can you summarize these instructions?"))
        XCTAssertNil(VoiceCommandParser.parse("   "))
        // "stop" only counts as a command on its own, not inside a longer request.
        XCTAssertNotEqual(VoiceCommandParser.parse("stop and find my bottle"), .stopSpeaking)
    }

    // MARK: Grounded answers never invent

    private func context(_ objects: [(String, Double, CGFloat)], running: Bool = true) -> AssistantContext {
        var snapshot = DetectionSnapshot()
        snapshot.objects = objects.map {
            DetectedObject(id: UUID(), name: $0.0, confidence: $0.1,
                           boundingBox: CGRect(x: $0.2 - 0.05, y: 0.4, width: 0.1, height: 0.2))
        }
        return AssistantContext(isCameraRunning: running, snapshot: snapshot)
    }

    func testEmptyContextAdmitsUncertainty() {
        let empty = context([])
        XCTAssertTrue(AssistantFacts.identify(empty).contains("can't identify"))
        XCTAssertTrue(AssistantFacts.visibleObjects(empty).contains("don't detect"))
        XCTAssertTrue(AssistantFacts.identify(context([], running: false)).contains("camera isn't running"))
    }

    func testObjectsDescribedWithPositionAndHedging() {
        let ctx = context([("bottle", 0.9, 0.5), ("apple", 0.4, 0.1)])
        let list = AssistantFacts.visibleObjects(ctx)
        XCTAssertTrue(list.contains("likely a bottle ahead"))
        XCTAssertTrue(list.contains("maybe an apple on your left"))
        XCTAssertTrue(AssistantFacts.identify(ctx).contains("bottle"))
        XCTAssertTrue(AssistantFacts.identify(ctx).contains("can be wrong"))
    }

    func testFindMatchesSpokenNamesToDetections() {
        let ctx = context([("bottle", 0.8, 0.8), ("cell phone", 0.7, 0.2), ("cup", 0.6, 0.5)])
        XCTAssertEqual(AssistantFacts.match("water bottle", in: ctx.objects)?.name, "bottle")
        XCTAssertEqual(AssistantFacts.match("phone", in: ctx.objects)?.name, "cell phone")
        XCTAssertEqual(AssistantFacts.match("mug", in: ctx.objects)?.name, "cup")
        XCTAssertEqual(AssistantFacts.match("bottles", in: ctx.objects)?.name, "bottle")
        XCTAssertNil(AssistantFacts.match("keys", in: ctx.objects))
        let found = AssistantFacts.find("water bottle", in: ctx)
        XCTAssertNotNil(found.match)
        XCTAssertTrue(found.answer.contains("on your right"))
        XCTAssertNil(AssistantFacts.find("keys", in: ctx).match)
    }

    // MARK: Safety

    func testSafetyNoteForConsumptionAndMedication() {
        XCTAssertTrue(AssistantFacts.withSafetyNote("That's an apple.", for: "Is this safe to eat?")
            .contains(AssistantFacts.safetyNote))
        XCTAssertTrue(AssistantFacts.needsSafetyNote("Take 2 tablets daily"))
        XCTAssertFalse(AssistantFacts.needsSafetyNote("Blue chair"))
    }

    // MARK: Locate and Explore flows

    func testTargetParserStripsRequests() {
        XCTAssertEqual(TargetParser.extract(from: "Can you help me find my water bottle please"), "water bottle")
        XCTAssertEqual(TargetParser.extract(from: "I'm looking for the keys"), "keys")
        XCTAssertEqual(TargetParser.extract(from: "Cup"), "cup")
    }

    func testFoundTrackerDebouncesContactWithHysteresis() {
        var tracker = FoundTracker()
        XCTAssertFalse(tracker.update(distance: 0.01, time: 0))
        XCTAssertFalse(tracker.update(distance: 0.01, time: 0.2))
        XCTAssertTrue(tracker.update(distance: 0.01, time: 0.35), "contact held past the dwell")
        XCTAssertTrue(tracker.update(distance: 0.04, time: 0.5), "inside the release band stays found")
        XCTAssertTrue(tracker.update(distance: 0.08, time: 0.6))
        XCTAssertFalse(tracker.update(distance: 0.08, time: 1.2), "clearly apart past the release time")
        XCTAssertFalse(tracker.update(distance: nil, time: 5))
    }

    func testFoundTrackerSupportsDepthAlignmentThresholdsAndTrackingLoss() {
        var tracker = FoundTracker(
            contactDistance: 0.06,
            releaseDistance: 0.12,
            dwell: 0.3,
            release: 0.5,
            lostTimeout: 2
        )
        XCTAssertFalse(tracker.update(distance: 0.05, time: 0))
        XCTAssertTrue(tracker.update(distance: 0.05, time: 0.35))
        XCTAssertTrue(tracker.update(distance: 0.10, time: 0.5), "depth alignment uses the wider release band")
        XCTAssertTrue(tracker.update(distance: 0.13, time: 0.6))
        XCTAssertFalse(tracker.update(distance: 0.13, time: 1.2))

        XCTAssertFalse(tracker.update(distance: 0.05, time: 2))
        XCTAssertTrue(tracker.update(distance: 0.05, time: 2.35))
        XCTAssertTrue(tracker.update(distance: nil, time: 4), "brief tracking loss preserves alignment")
        XCTAssertFalse(tracker.update(distance: nil, time: 4.5), "tracking loss resets after the configured timeout")
        XCTAssertFalse(tracker.update(distance: 0.05, time: 5), "contact must dwell again after tracking loss")
        XCTAssertTrue(tracker.update(distance: 0.05, time: 5.35))
    }

    func testObjectMaskEdgeCenterAndContains() throws {
        // 6 × 4 grid (row 0 = top) with a 2 × 2 block in the middle.
        var pixels = [Bool](repeating: false, count: 24)
        for (x, y) in [(2, 1), (3, 1), (2, 2), (3, 2)] { pixels[y * 6 + x] = true }
        let mask = try XCTUnwrap(ObjectMask(width: 6, height: 4, pixels: pixels))
        XCTAssertEqual(mask.edge.count, 4, "every cell of a 2 × 2 block touches the outside")
        XCTAssertTrue(mask.contains(CGPoint(x: 0.45, y: 0.5)))
        XCTAssertFalse(mask.contains(CGPoint(x: 0.05, y: 0.5)))
        XCTAssertTrue(mask.contains(mask.center))
        let nearest = try XCTUnwrap(mask.nearestEdgePoint(to: CGPoint(x: 0, y: 0.5)))
        XCTAssertLessThan(nearest.x, 0.5, "the nearest outline point is on the left side")
        XCTAssertNil(ObjectMask(width: 2, height: 2, pixels: [false, false, false, false]))
    }

    func testBundledSegmentationModelLoadsWithCocoClasses() {
        let segmenter = SegmentationDetector()
        XCTAssertEqual(segmenter.availableClasses.count, 80)
        XCTAssertTrue(segmenter.availableClasses.contains("bottle"))
        XCTAssertEqual(AssistantFacts.matchClass("water bottle", in: segmenter.availableClasses), "bottle")
    }

    func testSpokenTargetMapsToModelClass() {
        let classes = ["person", "bottle", "cup", "cell phone", "couch", "dining table", "car", "carrot"]
        XCTAssertEqual(AssistantFacts.matchClass("water bottle", in: classes), "bottle")
        XCTAssertEqual(AssistantFacts.matchClass("my phone", in: classes), "cell phone")
        XCTAssertEqual(AssistantFacts.matchClass("mug", in: classes), "cup")
        XCTAssertEqual(AssistantFacts.matchClass("sofa", in: classes), "couch")
        XCTAssertEqual(AssistantFacts.matchClass("car", in: classes), "car")
        XCTAssertNil(AssistantFacts.matchClass("keys", in: classes))
    }

    @MainActor
    func testExploreSummaryRequestCarriesLabelText() {
        let message = ExploreScreen.summaryRequest(for: ["Ibuprofen", "200 mg tablets"])
        XCTAssertTrue(message.contains("may contain misread characters"))
        XCTAssertTrue(message.contains("- 200 mg tablets"))
        XCTAssertTrue(message.contains("Summarize this item in one or two short sentences, then wait."))
    }

    func testTextConsolidatorKeepsLinesSeenInThreeScans() {
        var consolidator = TextConsolidator()
        let label = TextReading(text: "Oat Milk", midY: 0.8, minX: 0.2)
        let size = TextReading(text: "1 Litre", midY: 0.5, minX: 0.2)
        let misread = TextReading(text: "0at Mi1k", midY: 0.8, minX: 0.2)
        consolidator.add([label, size])
        consolidator.add([label, misread])
        XCTAssertEqual(consolidator.consolidated(), [], "nothing has been seen three times yet")
        consolidator.add([label, size])
        XCTAssertEqual(consolidator.consolidated(), ["Oat Milk"], "only lines seen in three scans count")
        consolidator.add([label, size])
        XCTAssertEqual(consolidator.consolidated(), ["Oat Milk", "1 Litre"], "top to bottom")
        consolidator.reset()
        XCTAssertEqual(consolidator.consolidated(), [])
    }
}
