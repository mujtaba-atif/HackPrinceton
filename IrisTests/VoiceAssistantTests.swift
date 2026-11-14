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
    func testExploreSummaryRequestCarriesTextAndFields() {
        var reading = LabelReading()
        reading.title = "Ibuprofen"
        reading.strength = "200 mg"
        reading.allLines = ["Ibuprofen", "200 mg tablets"]
        let message = ExploreScreen.summaryRequest(for: reading)
        XCTAssertTrue(message.contains("may contain misread characters"))
        XCTAssertTrue(message.contains("- 200 mg tablets"))
        XCTAssertTrue(message.contains("Strength: 200 mg"))
        XCTAssertTrue(ExploreScreen.persona.contains("Never say an item is safe"))
    }

    func testIrisWordmarkSplitsIntoLettersInPlace() {
        let rect = CGRect(x: 76.6, y: 270.9, width: 572.0, height: 126.3)
        let title = IrisLettering.layer(name: "Title", text: "IRIS", in: rect, color: .white)
        XCTAssertEqual(title.pieces.count, 4)
        XCTAssertTrue(rect.insetBy(dx: -1, dy: -1).contains(title.bounds))
        let label = IrisLettering.layer(name: "Label", text: "LOCATE", in: CGRect(x: 0, y: 0, width: 90, height: 300),
                                        color: .white, orientation: .upward)
        XCTAssertGreaterThan(label.bounds.height, label.bounds.width, "sideways label runs vertically")
    }
}
