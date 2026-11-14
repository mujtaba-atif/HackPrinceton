import CoreGraphics
import CoreVideo
import UIKit
import XCTest
@testable import Iris

// MARK: - Orientation analysis

final class LabelOrientationAnalyzerTests: XCTestCase {
    private let analyzer = LabelOrientationAnalyzer()
    private let wholeObject = CGRect(x: 0, y: 0, width: 1, height: 1)

    private func line(_ text: String = "METFORMIN HCL", x: CGFloat, width: CGFloat = 0.3,
                      y: CGFloat = 0.5, height: CGFloat = 0.06, confidence: Double = 0.9) -> RecognizedTextLine {
        RecognizedTextLine(text: text, confidence: confidence,
                           boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }

    private func decide(_ lines: [RecognizedTextLine], region: CGRect? = nil,
                        luminance: Double? = 0.5, distance: Double? = nil) -> LabelGuidanceDecision {
        analyzer.analyze(lines, objectRegion: region ?? wholeObject,
                         luminance: luminance, distanceMeters: distance).1
    }

    func testTextCutOffAtRightEdgeMeansTurnLeft() {
        let lines = [line(x: 0.72, width: 0.27), line("500 MG TABLET", x: 0.75, width: 0.25, y: 0.4)]
        XCTAssertEqual(decide(lines), .turnLeft)
    }

    func testTextCutOffAtLeftEdgeMeansTurnRight() {
        let lines = [line(x: 0.0, width: 0.25), line("500 MG TABLET", x: 0.02, width: 0.22, y: 0.4)]
        XCTAssertEqual(decide(lines), .turnRight)
    }

    func testOffCenterTextWithoutCutoffStillTurnsTowardIt() {
        XCTAssertEqual(decide([line(x: 0.55, width: 0.3)]), .turnLeft)
        XCTAssertEqual(decide([line(x: 0.15, width: 0.3)]), .turnRight)
    }

    func testCenteredReadableLabelIsReady() {
        let lines = [line("ACME PHARMACY", x: 0.3, width: 0.4, y: 0.7),
                     line("METFORMIN 500 MG", x: 0.25, width: 0.5, y: 0.5),
                     line("TAKE 1 TABLET DAILY", x: 0.3, width: 0.4, y: 0.3)]
        XCTAssertEqual(decide(lines), .ready)
    }

    func testLabelSpanningBothEdgesFacesCamera() {
        let lines = [line("METFORMIN HYDROCHLORIDE 500 MG", x: 0.02, width: 0.96),
                     line("TAKE ONE TABLET BY MOUTH", x: 0.2, width: 0.6, y: 0.4)]
        XCTAssertEqual(decide(lines), .ready)
    }

    func testNoTextSearchesAndDarknessAsksForLight() {
        XCTAssertEqual(decide([]), .searching)
        XCTAssertEqual(decide([], luminance: 0.05), .needsLight)
    }

    func testNoiseIsIgnored() {
        let noise = [line("~", x: 0.4, width: 0.1), line("ACME", x: 0.4, confidence: 0.1)]
        XCTAssertEqual(decide(noise), .searching)
    }

    func testSmallCenteredTextAsksToMoveCloser() {
        let lines = [line("TINY", x: 0.42, width: 0.16, height: 0.01, confidence: 0.4)]
        XCTAssertEqual(decide(lines), .moveCloser)
    }

    func testFarAwayUnreadableTextAsksToMoveCloser() {
        let lines = [line("ACME", x: 0.4, width: 0.2, confidence: 0.4)]
        XCTAssertEqual(decide(lines, distance: 1.2), .moveCloser)
    }

    func testCenteredWeakTextAsksToHoldSteady() {
        let lines = [line("METF0RM1N 5OO", x: 0.3, width: 0.4, confidence: 0.35)]
        XCTAssertEqual(decide(lines), .holdSteady)
    }

    func testEdgesAreMeasuredAgainstTheObjectNotThePaddedCrop() {
        let plan = LabelCropPlanner.plan(objectBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.4))
        let region = plan.objectRegion
        // Text hugging the bottle's right edge sits well inside the padded crop.
        let atBottleEdge = line(x: region.maxX - 0.2 * region.width, width: 0.2 * region.width)
        XCTAssertLessThan(atBottleEdge.boundingBox.maxX, 0.95)
        XCTAssertEqual(decide([atBottleEdge], region: region), .turnLeft)
    }

    func testReadinessScoreRisesAsLabelCenters() {
        let edge = analyzer.readiness(for: [line(x: 0.72, width: 0.27)], objectRegion: wholeObject)
        let centered = analyzer.readiness(for: [line("METFORMIN 500 MG TABLETS", x: 0.25, width: 0.5)],
                                          objectRegion: wholeObject)
        XCTAssertGreaterThan(centered.score, edge.score)
        XCTAssertEqual(LabelReadiness.empty.score, 0)
    }
}

// MARK: - Crop planning

final class LabelCropPlannerTests: XCTestCase {
    func testWithoutObjectUsesCenterOfFrame() {
        let plan = LabelCropPlanner.plan(objectBox: nil)
        XCTAssertFalse(plan.usesDetectedObject)
        XCTAssertEqual(plan.cropRect, LabelCropPlanner.centerRegion)
        XCTAssertEqual(plan.objectRegion, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testObjectRegionIsExpressedInsideThePaddedCrop() {
        let box = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.5)
        let plan = LabelCropPlanner.plan(objectBox: box, padding: 0.1)
        XCTAssertTrue(plan.usesDetectedObject)
        XCTAssertEqual(plan.cropRect.minX, 0.38, accuracy: 1e-9)
        XCTAssertEqual(plan.cropRect.width, 0.24, accuracy: 1e-9)
        XCTAssertEqual(plan.objectRegion.minX, 0.02 / 0.24, accuracy: 1e-9)
        XCTAssertEqual(plan.objectRegion.width, 0.2 / 0.24, accuracy: 1e-9)
    }

    func testCropIsClippedAtImageEdge() {
        let plan = LabelCropPlanner.plan(objectBox: CGRect(x: 0.9, y: 0.0, width: 0.1, height: 0.3))
        XCTAssertLessThanOrEqual(plan.cropRect.maxX, 1)
        XCTAssertGreaterThanOrEqual(plan.cropRect.minY, 0)
        XCTAssertEqual(plan.objectRegion.maxX, 1, accuracy: 1e-9)
    }

    func testTinyOrInvalidBoxFallsBackToCenter() {
        XCTAssertFalse(LabelCropPlanner.plan(objectBox: CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.2)).usesDetectedObject)
        XCTAssertFalse(LabelCropPlanner.plan(objectBox: CGRect(x: .nan, y: 0, width: 0.2, height: 0.2)).usesDetectedObject)
    }
}

// MARK: - Speech stabilization

final class LabelGuidanceStabilizerTests: XCTestCase {
    private func readiness(_ centroid: Double?) -> LabelReadiness {
        var value = LabelReadiness()
        if let centroid {
            value.lineCount = 1
            value.characterCount = 10
            value.meanConfidence = 0.8
            value.horizontalCentroid = centroid
        }
        return value
    }

    func testDecisionMustHoldForThreeFrames() {
        var stabilizer = LabelGuidanceStabilizer()
        XCTAssertNil(stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: 0))
        XCTAssertNil(stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: 0.2))
        XCTAssertEqual(stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: 0.4), .instruct(.turnLeft))
        XCTAssertEqual(stabilizer.current, .turnLeft)
    }

    func testSingleFrameFlickerDoesNotChangeInstruction() {
        var stabilizer = LabelGuidanceStabilizer()
        for time in [0, 0.2, 0.4] { _ = stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: time) }
        XCTAssertNil(stabilizer.update(decision: .turnRight, readiness: readiness(-0.6), at: 0.6))
        XCTAssertNil(stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: 0.8))
        XCTAssertNil(stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: 1.0))
        XCTAssertEqual(stabilizer.current, .turnLeft)
    }

    func testStandingInstructionIsRemindedButNotRepeatedEarly() {
        var stabilizer = LabelGuidanceStabilizer()
        for time in [0, 0.2, 0.4] { _ = stabilizer.update(decision: .holdSteady, readiness: readiness(0), at: time) }
        XCTAssertNil(stabilizer.update(decision: .holdSteady, readiness: readiness(0), at: 2.0))
        XCTAssertNil(stabilizer.update(decision: .holdSteady, readiness: readiness(0), at: 5.0))
        XCTAssertEqual(stabilizer.update(decision: .holdSteady, readiness: readiness(0), at: 5.5), .instruct(.holdSteady))
    }

    func testTurningTheRightWayIsEncouraged() {
        var stabilizer = LabelGuidanceStabilizer()
        for time in [0, 0.2, 0.4] { _ = stabilizer.update(decision: .turnLeft, readiness: readiness(0.7), at: time) }
        var events: [LabelGuidanceEvent] = []
        var centroid = 0.7
        for step in 1...20 {
            centroid -= 0.05
            if let event = stabilizer.update(decision: .turnLeft, readiness: readiness(centroid),
                                             at: 0.4 + Double(step) * 0.2) {
                events.append(event)
            }
        }
        XCTAssertTrue(events.contains(.encourage))
        XCTAssertFalse(events.contains(.wrongWay))
    }

    func testTurningTheWrongWayIsCorrected() {
        var stabilizer = LabelGuidanceStabilizer()
        for time in [0, 0.2, 0.4] { _ = stabilizer.update(decision: .turnLeft, readiness: readiness(0.3), at: time) }
        var events: [LabelGuidanceEvent] = []
        var centroid = 0.3
        for step in 1...8 {
            centroid += 0.06
            if let event = stabilizer.update(decision: .turnLeft, readiness: readiness(centroid),
                                             at: 0.4 + Double(step) * 0.2) {
                events.append(event)
            }
        }
        XCTAssertEqual(events.first, .wrongWay)
        XCTAssertFalse(events.contains(.encourage))
    }

    func testJitterWithoutNetMovementIsNotWrongWay() {
        var stabilizer = LabelGuidanceStabilizer()
        for time in [0, 0.2, 0.4] { _ = stabilizer.update(decision: .turnRight, readiness: readiness(-0.5), at: time) }
        var events: [LabelGuidanceEvent] = []
        for step in 1...15 {
            let centroid = step.isMultiple(of: 2) ? -0.5 : -0.54
            if let event = stabilizer.update(decision: .turnRight, readiness: readiness(centroid),
                                             at: 0.4 + Double(step) * 0.2) {
                events.append(event)
            }
        }
        XCTAssertFalse(events.contains(.wrongWay))
        XCTAssertFalse(events.contains(.encourage))
    }

    func testSearchingSweepsThenGivesUp() {
        var stabilizer = LabelGuidanceStabilizer()
        var events: [LabelGuidanceEvent] = []
        var time = 0.0
        while time <= 17 {
            if let event = stabilizer.update(decision: .searching, readiness: readiness(nil), at: time) {
                events.append(event)
            }
            time += 0.2
        }
        XCTAssertEqual(events.first, .instruct(.searching))
        XCTAssertEqual(events.filter { $0 == .trySweepOtherWay }.count, 1)
        XCTAssertEqual(events.last, .noTextFound)
    }

    func testFindingTextResetsTheSweep() {
        var stabilizer = LabelGuidanceStabilizer()
        var time = 0.0
        while time < 7 { _ = stabilizer.update(decision: .searching, readiness: readiness(nil), at: time); time += 0.2 }
        for _ in 0..<3 { _ = stabilizer.update(decision: .turnLeft, readiness: readiness(0.6), at: time); time += 0.2 }
        var events: [LabelGuidanceEvent] = []
        let resumed = time
        while time < resumed + 7 {
            if let event = stabilizer.update(decision: .searching, readiness: readiness(nil), at: time) {
                events.append(event)
            }
            time += 0.2
        }
        XCTAssertFalse(events.contains(.trySweepOtherWay))
        XCTAssertFalse(events.contains(.noTextFound))
    }
}

// MARK: - Spoken phrases

final class LabelGuidancePhrasesTests: XCTestCase {
    func testConventionIsExplainedOnlyWhenRequested() {
        let first = LabelGuidancePhrases.phrase(for: .instruct(.turnLeft), searchDirection: .left, explainConvention: true)
        let later = LabelGuidancePhrases.phrase(for: .instruct(.turnLeft), searchDirection: .left, explainConvention: false)
        XCTAssertEqual(first, "Turn it left. That means the front of it moves toward your left.")
        XCTAssertEqual(later, "Turn it left.")
    }

    func testSearchPhraseFollowsSweepDirection() {
        let phrase = LabelGuidancePhrases.phrase(for: .trySweepOtherWay, searchDirection: .right, explainConvention: false)
        XCTAssertTrue(phrase?.contains("to the right") ?? false)
        XCTAssertNil(LabelGuidancePhrases.phrase(for: .noTextFound, searchDirection: .left, explainConvention: false))
    }
}

// MARK: - Merging text across frames

final class LabelTextAccumulatorTests: XCTestCase {
    private func line(_ text: String, y: CGFloat = 0.5, confidence: Double = 0.8) -> RecognizedTextLine {
        RecognizedTextLine(text: text, confidence: confidence, boundingBox: CGRect(x: 0.2, y: y, width: 0.5, height: 0.05))
    }

    func testNearDuplicatesMergeKeepingTheMoreConfidentReading() {
        var accumulator = LabelTextAccumulator()
        accumulator.add([line("METF0RMIN 500 MG", confidence: 0.5)])
        accumulator.add([line("METFORMIN 500 MG", confidence: 0.9)])
        XCTAssertEqual(accumulator.lines.count, 1)
        XCTAssertEqual(accumulator.lines.first?.text, "METFORMIN 500 MG")
        XCTAssertEqual(accumulator.lines.first?.seenCount, 2)
    }

    func testFragmentsMergeIntoTheCompleteLine() {
        var accumulator = LabelTextAccumulator()
        accumulator.add([line("TAKE 1 TAB", confidence: 0.9)])
        accumulator.add([line("TAKE 1 TABLET BY MOUTH DAILY", confidence: 0.7)])
        accumulator.add([line("BY MOUTH", confidence: 0.95)])
        XCTAssertEqual(accumulator.lines.count, 1)
        XCTAssertEqual(accumulator.lines.first?.text, "TAKE 1 TABLET BY MOUTH DAILY")
    }

    func testDistinctLinesAreOrderedTopToBottom() {
        var accumulator = LabelTextAccumulator()
        accumulator.add([line("TAKE 1 TABLET DAILY", y: 0.3), line("ACME PHARMACY", y: 0.8)])
        accumulator.add([line("METFORMIN 500 MG", y: 0.55)])
        XCTAssertEqual(accumulator.orderedLines.map(\.text),
                       ["ACME PHARMACY", "METFORMIN 500 MG", "TAKE 1 TABLET DAILY"])
    }

    func testWhitespaceAndShortNoiseAreCleaned() {
        var accumulator = LabelTextAccumulator()
        accumulator.add([line("  ACME    PHARMACY "), line("~")])
        XCTAssertEqual(accumulator.lines.map(\.text), ["ACME PHARMACY"])
    }
}

// MARK: - Interpreting label text

final class OfflineLabelInterpreterTests: XCTestCase {
    private func lines(_ texts: [(String, Double)]) -> [AccumulatedTextLine] {
        texts.enumerated().map { index, item in
            AccumulatedTextLine(text: item.0, confidence: 0.9, seenCount: 1, averageHeight: item.1,
                                averageMidY: 1 - Double(index) * 0.05, firstSeenOrder: index)
        }
    }

    private var prescription: [AccumulatedTextLine] {
        lines([("ACME PHARMACY  555-0100", 0.04),
               ("Rx# 6012345", 0.04),
               ("JANE Q PUBLIC", 0.09), // Patient names are often the largest text.
               ("METFORMIN HCL 500 MG TAB", 0.06),
               ("TAKE 1 TABLET BY MOUTH TWICE", 0.05),
               ("DAILY WITH MEALS", 0.05),
               ("QTY: 60   REFILLS: 2", 0.04),
               ("DR. ALAN SMITH", 0.04),
               ("DISCARD AFTER 03/03/2027", 0.04),
               ("MAY CAUSE DIZZINESS", 0.04),
               ("DO NOT DRINK ALCOHOL", 0.04)])
    }

    func testPrescriptionFieldsAreExtracted() {
        let reading = OfflineLabelInterpreter().read(prescription)
        XCTAssertTrue(reading.isLikelyPrescription)
        XCTAssertEqual(reading.title, "METFORMIN HCL 500 MG TAB")
        XCTAssertEqual(reading.strength, "500 MG")
        XCTAssertEqual(reading.directions, "TAKE 1 TABLET BY MOUTH TWICE DAILY WITH MEALS")
        XCTAssertEqual(reading.rxNumber, "6012345")
        XCTAssertEqual(reading.quantity, "60")
        XCTAssertEqual(reading.refills, "2 refills")
        XCTAssertEqual(reading.prescriber, "ALAN SMITH")
        XCTAssertEqual(reading.pharmacy, "ACME PHARMACY  555-0100")
        XCTAssertEqual(reading.discardOrExpiration, "March 3, 2027")
        XCTAssertEqual(reading.warnings, ["MAY CAUSE DIZZINESS", "DO NOT DRINK ALCOHOL"])
        XCTAssertTrue(reading.missingImportantFields.isEmpty)
    }

    func testSummaryLeadsWithDrugAndNeverReadsPatientName() {
        let summary = LabelReadingSpeech.summary(OfflineLabelInterpreter().read(prescription))
        XCTAssertTrue(summary.hasPrefix("METFORMIN HCL 500 milligrams tablet."), summary)
        XCTAssertTrue(summary.contains("Discard after March 3, 2027."))
        XCTAssertTrue(summary.contains("confirm with your pharmacist"))
        XCTAssertFalse(summary.contains("JANE"))
        XCTAssertFalse(summary.lowercased().contains("safe"))
    }

    func testDetailsIncludeSecondaryFields() {
        let details = LabelReadingSpeech.details(OfflineLabelInterpreter().read(prescription))
        XCTAssertTrue(details.contains("Prescription number 6012345."))
        XCTAssertTrue(details.contains("2 refills."))
        XCTAssertTrue(details.contains("Prescriber: ALAN SMITH."))
    }

    func testMissingDirectionsAreReported() {
        let reading = OfflineLabelInterpreter().read(lines([("Rx# 778899", 0.04), ("LISINOPRIL 10 MG", 0.06),
                                                            ("REFILLS: 0", 0.04)]))
        XCTAssertEqual(reading.refills, "No refills")
        XCTAssertEqual(reading.missingImportantFields, ["directions"])
        XCTAssertTrue(LabelReadingSpeech.summary(reading).contains("I couldn't read the directions"))
    }

    func testPrescriptionWithoutStrengthDoesNotGuessName() {
        let reading = OfflineLabelInterpreter().read(lines([("JANE Q PUBLIC", 0.09), ("Rx# 123456", 0.04),
                                                            ("TAKE 1 CAPSULE DAILY", 0.05)]))
        XCTAssertNil(reading.title)
        XCTAssertTrue(LabelReadingSpeech.summary(reading).contains("I couldn't read the medication name"))
    }

    func testGroceryItemUsesLargestText() {
        let reading = OfflineLabelInterpreter().read(lines([("NET WT 10.75 OZ", 0.03), ("Tomato Soup", 0.12),
                                                            ("Condensed", 0.05), ("BEST BY 01/15/2027", 0.03)]))
        XCTAssertFalse(reading.isLikelyPrescription)
        XCTAssertEqual(reading.title, "Tomato Soup")
        XCTAssertEqual(reading.discardOrExpiration, "January 15, 2027")
        XCTAssertFalse(LabelReadingSpeech.summary(reading).contains("pharmacist"))
    }

    func testLookalikeWordsAreNotMisreadAsFields() {
        let reading = OfflineLabelInterpreter().read(lines([("Rx ONLY", 0.04), ("DRUG STORE BRAND", 0.05),
                                                            ("IBUPROFEN 200 MG", 0.07)]))
        XCTAssertNil(reading.rxNumber)
        XCTAssertNil(reading.prescriber)
    }

    func testEmptyTextGivesHonestSummary() {
        let reading = OfflineLabelInterpreter().read([])
        XCTAssertFalse(reading.hasAnyText)
        XCTAssertTrue(LabelReadingSpeech.summary(reading).hasPrefix("I couldn't read any text"))
    }

    func testUncertainTitleIsFlagged() {
        var low = lines([("IBUPROFEN 200 MG", 0.07)])
        low[0].confidence = 0.4
        let reading = OfflineLabelInterpreter().read(low)
        XCTAssertTrue(reading.titleIsUncertain)
        XCTAssertTrue(LabelReadingSpeech.summary(reading).hasPrefix("I think this says"))
    }
}

// MARK: - Camera frame cropping and real text recognition

final class LabelFrameProcessorTests: XCTestCase {
    /// Native landscape buffer with a white patch exactly where the upright `box` maps in sensor space.
    private func pixelBuffer(whiteAtUpright box: CGRect, width: Int = 400, height: Int = 300) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true,
                          kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer),
                       kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        let sensor = DetectionGeometry.sensorRect(box) // top-left origin, native landscape
        for row in 0..<height {
            for column in 0..<width {
                let x = (Double(column) + 0.5) / Double(width)
                let y = (Double(row) + 0.5) / Double(height)
                let value: UInt8 = sensor.contains(CGPoint(x: x, y: y)) ? 255 : 0
                let offset = row * rowBytes + column * 4
                base[offset] = value; base[offset + 1] = value; base[offset + 2] = value; base[offset + 3] = 255
            }
        }
        return pixels
    }

    func testCropMatchesDetectorOrientation() async throws {
        let box = CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.25)
        let buffer = try pixelBuffer(whiteAtUpright: box)
        let processor = LabelFrameProcessor()
        let inside = await processor.makeCrop(from: buffer, region: box.insetBy(dx: 0.03, dy: 0.03))
        let elsewhere = await processor.makeCrop(from: buffer, region: CGRect(x: 0.55, y: 0.1, width: 0.3, height: 0.25))
        XCTAssertGreaterThan(try XCTUnwrap(inside?.luminance), 0.9)
        XCTAssertLessThan(try XCTUnwrap(elsewhere?.luminance), 0.1)
    }

    func testSmallCropsAreUpscaledForReading() async throws {
        let buffer = try pixelBuffer(whiteAtUpright: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let crop = await LabelFrameProcessor().makeCrop(from: buffer, region: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let image = try XCTUnwrap(crop?.image)
        XCTAssertGreaterThan(max(image.width, image.height), 80)
    }

    func testRecognizesRenderedLabelText() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 72),
                                                             .foregroundColor: UIColor.black]
            NSString(string: "METFORMIN 500 MG").draw(at: CGPoint(x: 40, y: 40), withAttributes: attributes)
            NSString(string: "TAKE 1 TABLET").draw(at: CGPoint(x: 40, y: 160), withAttributes: attributes)
        }
        let lines = try OCRService().recognizeText(in: try XCTUnwrap(image.cgImage), level: .accurate)
        let text = lines.map(\.text).joined(separator: " ").uppercased()
        XCTAssertTrue(text.contains("METFORMIN"), text)
        XCTAssertTrue(text.contains("TABLET"), text)
        // Vision's bottom-left origin: the first drawn line is higher on the image.
        let metformin = try XCTUnwrap(lines.first { $0.text.uppercased().contains("METFORMIN") })
        let tablet = try XCTUnwrap(lines.first { $0.text.uppercased().contains("TABLET") })
        XCTAssertGreaterThan(metformin.boundingBox.midY, tablet.boundingBox.midY)
    }
}

// MARK: - Service lifecycle

private final class ReleaseFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

@MainActor
private final class SilentCues: LabelGuidanceCueing {
    var successes = 0
    var failures = 0
    func prepare() {}
    func tick(readiness: Double) {}
    func success() { successes += 1 }
    func failure() { failures += 1 }
}

@MainActor
final class LabelGuidanceServiceTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testEndedCameraStreamFailsAndReleases() async {
        let cues = SilentCues()
        let service = LabelGuidanceService(cues: cues)
        let (stream, continuation) = AsyncStream.makeStream(of: CameraFrame.self)
        service.start(frames: stream, target: { nil })
        XCTAssertEqual(service.state, .guiding(.searching))
        continuation.finish()
        await waitUntil { service.state == .failed(.cameraStopped) }
        XCTAssertEqual(service.state, .failed(.cameraStopped))
        XCTAssertEqual(cues.failures, 1)
        service.stop()
    }

    func testTimeoutFailsAndReleasesFrameStream() async {
        var configuration = LabelGuidanceService.Configuration()
        configuration.guidanceTimeout = 0.3
        let service = LabelGuidanceService(cues: SilentCues(), configuration: configuration)
        let (stream, continuation) = AsyncStream.makeStream(of: CameraFrame.self)
        let released = ReleaseFlag()
        continuation.onTermination = { _ in released.set() }
        service.start(frames: stream, target: { nil })
        await waitUntil { service.state == .failed(.timedOut) }
        XCTAssertEqual(service.state, .failed(.timedOut))
        await waitUntil { released.isSet }
        XCTAssertTrue(released.isSet, "The camera frame stream must be released after failing")
        service.stop()
    }

    func testStopReturnsToIdleAndReleasesFrameStream() async {
        let service = LabelGuidanceService(cues: SilentCues())
        let (stream, continuation) = AsyncStream.makeStream(of: CameraFrame.self)
        let released = ReleaseFlag()
        continuation.onTermination = { _ in released.set() }
        service.start(frames: stream, target: { nil })
        service.stop()
        XCTAssertEqual(service.state, .idle)
        XCTAssertNil(service.reading)
        await waitUntil { released.isSet }
        XCTAssertTrue(released.isSet)
    }

    func testReadNowOnlyAppliesWhileGuiding() {
        let service = LabelGuidanceService(cues: SilentCues())
        service.readNow()
        XCTAssertEqual(service.state, .idle)
        let (stream, _) = AsyncStream.makeStream(of: CameraFrame.self)
        service.start(frames: stream, target: { nil })
        service.readNow()
        XCTAssertEqual(service.state, .capturing)
        service.stop()
    }
}
