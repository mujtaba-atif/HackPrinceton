import XCTest
@testable import Iris

final class VoiceAssistantTests: XCTestCase {
    private func label(_ texts: [String], confidence: Double = 0.9, focus: String? = nil) -> OCRResult {
        OCRResult(lines: texts.enumerated().map { index, text in
            AccumulatedTextLine(text: text, confidence: confidence, seenCount: 2, averageHeight: 0.05,
                                averageMidY: 0.9 - Double(index) * 0.1, firstSeenOrder: index)
        }, focusName: focus, timestamp: 1)
    }

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

    private func context(_ objects: [(String, Double, CGFloat)], running: Bool = true, ocr: OCRResult? = nil) -> AssistantContext {
        var snapshot = DetectionSnapshot()
        snapshot.objects = objects.map {
            DetectedObject(id: UUID(), name: $0.0, confidence: $0.1,
                           boundingBox: CGRect(x: $0.2 - 0.05, y: 0.4, width: 0.1, height: 0.2))
        }
        return AssistantContext(isCameraRunning: running, snapshot: snapshot, ocr: ocr)
    }

    func testEmptyContextAdmitsUncertainty() {
        let empty = context([])
        XCTAssertTrue(AssistantFacts.identify(empty).contains("can't identify"))
        XCTAssertTrue(AssistantFacts.visibleObjects(empty).contains("don't detect"))
        XCTAssertTrue(AssistantFacts.identify(context([], running: false)).contains("camera isn't running"))
        XCTAssertTrue(AssistantFacts.answer("what does the label say", context: empty).contains("haven't read"))
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
        XCTAssertTrue(AssistantFacts.answer("Is this safe to eat?", context: context([("apple", 0.9, 0.5)]))
            .contains(AssistantFacts.safetyNote))
        let reading = label(["Take 2 tablets daily"])
        XCTAssertTrue(AssistantFacts.describeText(.result(reading)).contains(AssistantFacts.safetyNote))
        XCTAssertFalse(AssistantFacts.visibleObjects(context([("chair", 0.9, 0.5)])).contains(AssistantFacts.safetyNote))
    }

    // MARK: ElevenLabs conversation behaviour

    func testSpokenEndPhrasesOnlyWhenWholeUtterance() {
        XCTAssertTrue(AssistantConfiguration.isEndRequest("Goodbye"))
        XCTAssertTrue(AssistantConfiguration.isEndRequest("Okay, I'm done, thanks!"))
        XCTAssertTrue(AssistantConfiguration.isEndRequest("End the conversation please"))
        XCTAssertFalse(AssistantConfiguration.isEndRequest("Go back to the bottle on the left"))
        XCTAssertFalse(AssistantConfiguration.isEndRequest("What does the exit sign say"))
        XCTAssertFalse(AssistantConfiguration.isEndRequest(""))
    }

    func testReadLabelToolTextFlagsMisreadsAndSafety() {
        let result = label(["Ibuprofen 200 mg"], confidence: 0.4, focus: "bottle")
        let text = AssistantFacts.toolText(for: .result(result))
        XCTAssertTrue(text.hasPrefix("Read in reading order; may contain misread characters"))
        XCTAssertTrue(text.contains("selected bottle"))
        XCTAssertTrue(text.contains("- Ibuprofen 200 mg"))
        XCTAssertTrue(text.contains("confidence was low"))
        XCTAssertTrue(AssistantFacts.toolText(for: .noText(hint: "Hold it closer.")).contains("Hold it closer"))
    }

    @MainActor
    func testReadLabelHandOffMessage() {
        let result = label(["Oat Milk"])
        let message = VoiceAssistantCoordinator.describeRequest(for: .result(result))
        XCTAssertTrue(message.contains("- Oat Milk"))
        XCTAssertTrue(message.contains("may contain misread characters"))
        XCTAssertTrue(VoiceAssistantCoordinator.describeRequest(for: .noText(hint: "No text.")).contains("No text."))
    }
}
