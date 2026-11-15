import XCTest
import CoreVideo
@testable import Iris

// MARK: - Describing what to look for

final class TargetAppearanceTests: XCTestCase {
    func testPillsAreDescribedByTheCatalogNotTheDetector() throws {
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "pills"))
        XCTAssertEqual(pills.source, .catalog)
        XCTAssertFalse(pills.usesDetector)
        XCTAssertEqual(pills.classifierLabels, ["medicine"])
        XCTAssertEqual(pills.size, .tiny)
        XCTAssertTrue(pills.isSearchable)
    }

    /// A pill bottle is a bottle to the detector, but so is every other bottle.
    func testPillBottleSearchesBottlesByAppearance() throws {
        let bottle = try XCTUnwrap(AppearanceCatalog.appearance(for: "pill bottle"))
        XCTAssertEqual(bottle.source, .catalog)
        XCTAssertEqual(bottle.detectorClasses, ["bottle"])
        XCTAssertTrue(bottle.colors.contains(.orange))
    }

    func testDetectorClassesMatchWholeWordsOnly() {
        XCTAssertNil(AppearanceCatalog.detectorClass(for: "scarf"), "not a car")
        XCTAssertNil(AppearanceCatalog.detectorClass(for: "catalog"), "not a cat")
        XCTAssertEqual(AppearanceCatalog.detectorClass(for: "mug"), "cup")
        XCTAssertEqual(AppearanceCatalog.detectorClass(for: "bottles"), "bottle")
    }

    /// The model writes some class names run together; the words in them still count.
    func testRunTogetherClassNamesMatchTheirWords() {
        XCTAssertEqual(AppearanceCatalog.detectorClass(for: "tv"), "tvmonitor")
        XCTAssertEqual(AppearanceCatalog.detectorClass(for: "television"), "tvmonitor")
        XCTAssertEqual(AppearanceCatalog.detectorClass(for: "the table"), "diningtable")
        XCTAssertEqual(AppearanceCatalog.detectorClass(for: "plant"), "pottedplant")
    }

    /// The last word is the thing itself, so "glass" and "orange" there are names, not looks.
    func testTheLastWordIsTheNameNotADescription() throws {
        XCTAssertEqual(try XCTUnwrap(AppearanceCatalog.appearance(for: "wine glass")).source, .detector("wine glass"))
        XCTAssertEqual(try XCTUnwrap(AppearanceCatalog.appearance(for: "orange")).source, .detector("orange"))
        let bottle = try XCTUnwrap(AppearanceCatalog.appearance(for: "glass bottle"))
        XCTAssertEqual(bottle.detectorClasses, ["bottle"])
        XCTAssertEqual(bottle.textures, [.translucent])
        XCTAssertEqual(try XCTUnwrap(AppearanceCatalog.appearance(for: "orange pills")).colors, [.orange])
    }

    func testDetectorClassesStillUseTheDetector() throws {
        XCTAssertEqual(try XCTUnwrap(AppearanceCatalog.appearance(for: "water bottle")).source, .detector("bottle"))
        XCTAssertEqual(try XCTUnwrap(AppearanceCatalog.appearance(for: "phone")).source, .detector("cell phone"))
        XCTAssertEqual(try XCTUnwrap(AppearanceCatalog.appearance(for: "cup")).source, .detector("cup"))
    }

    /// "The red cup" among several cups: still the detector's class, but searched by color.
    func testDescribedDetectorClassIsSearchedByAppearance() throws {
        let cup = try XCTUnwrap(AppearanceCatalog.appearance(for: "red cup"))
        XCTAssertFalse(cup.usesDetector)
        XCTAssertEqual(cup.detectorClasses, ["cup"])
        XCTAssertEqual(cup.colors, [.red])
    }

    func testUsersWordsOverrideTheCatalogsGuess() throws {
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "blue pills"))
        XCTAssertEqual(pills.colors, [.blue])
        XCTAssertEqual(pills.classifierLabels, ["medicine"])
    }

    func testClassifierLabelsNamedInTheRequest() throws {
        let labels: Set<String> = ["board_game", "umbrella", "stapler"]
        let game = try XCTUnwrap(AppearanceCatalog.appearance(for: "board game", classifierLabels: labels))
        XCTAssertEqual(game.source, .words)
        XCTAssertEqual(game.classifierLabels, ["board_game"])
        XCTAssertNil(AppearanceCatalog.appearance(for: "flux capacitor", classifierLabels: labels))
    }

    func testADescriptionAloneIsSearchable() throws {
        let box = try XCTUnwrap(AppearanceCatalog.appearance(for: "small blue box"))
        XCTAssertEqual(box.colors, [.blue])
        XCTAssertEqual(box.size, .small)
        XCTAssertTrue(box.isSearchable)
    }

    func testAppearanceWordsAreParsedOut() {
        let words = AppearanceWords(parsing: "tiny shiny gold round thing")
        XCTAssertEqual(words.size, .tiny)
        XCTAssertEqual(words.colors, [.yellow])
        XCTAssertEqual(words.textures, [.shiny])
        XCTAssertEqual(words.shapes, [.round])
        XCTAssertEqual(words.remainder, "thing")
    }

    func testSpokenLook() throws {
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "pills"))
        XCTAssertEqual(pills.spokenLook, "tiny, round or elongated and white, yellow or orange")
    }

    func testLanguageModelWordsAreKeptToWhatTheSearchUnderstands() {
        let look = AppearanceDescriber.appearance(
            name: "hearing aid", lookalikes: ["earbud", "headphones", "coin"], colors: ["Beige", "gray", "teal"],
            size: "tiny", shape: "irregular", texture: "smooth", container: "box",
            classifierLabels: ["headphones", "coin", "earbud_case"]
        )
        XCTAssertEqual(look.source, .languageModel)
        XCTAssertEqual(look.classifierLabels, ["headphones", "coin"])
        XCTAssertEqual(look.colors, [.gray], "Only the named colors the search measures")
        XCTAssertEqual(look.size, .tiny)
        XCTAssertEqual(look.detectorClasses, [], "\"box\" isn't a detector class")
        let bottled = AppearanceDescriber.appearance(name: "eye drops", lookalikes: [], colors: [], size: "small",
                                                     shape: "elongated", texture: "shiny", container: "bottle",
                                                     classifierLabels: [])
        XCTAssertEqual(bottled.detectorClasses, ["bottle"])
    }

    /// Known items never wait on the language model.
    func testDescriberUsesTheCatalogFirst() async throws {
        let described = await AppearanceDescriber.describe("pills", classifierLabels: [])
        let pills = try XCTUnwrap(described)
        XCTAssertEqual(pills.source, .catalog)
    }
}

// MARK: - Color, texture, shape and size

final class AppearanceAnalyzerTests: XCTestCase {
    func testNamedColors() {
        XCTAssertEqual(AppearanceAnalyzer.color(red: 250, green: 250, blue: 248), .white)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 20, green: 20, blue: 25), .black)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 128, green: 128, blue: 130), .gray)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 220, green: 30, blue: 30), .red)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 255, green: 140, blue: 0), .orange)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 240, green: 220, blue: 40), .yellow)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 40, green: 180, blue: 60), .green)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 30, green: 80, blue: 220), .blue)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 130, green: 50, blue: 200), .purple)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 255, green: 170, blue: 190), .pink)
        XCTAssertEqual(AppearanceAnalyzer.color(red: 120, green: 70, blue: 30), .brown)
    }

    /// 40 × 40 RGBA, row 0 at the top. `paint` gets (x, y) in Vision coordinates.
    private func bitmap(_ paint: (Double, Double) -> (UInt8, UInt8, UInt8)) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: 40 * 40 * 4)
        for row in 0..<40 {
            for column in 0..<40 {
                let (r, g, b) = paint((Double(column) + 0.5) / 40, 1 - (Double(row) + 0.5) / 40)
                let i = (row * 40 + column) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b
            }
        }
        return pixels
    }

    private func sample(_ pixels: [UInt8], _ region: CGRect) throws -> AppearanceSample {
        try XCTUnwrap(pixels.withUnsafeBufferPointer {
            AppearanceAnalyzer.sample(rgba: $0, width: 40, height: 40, bytesPerRow: 160, region: region)
        })
    }

    func testSamplingUsesVisionCoordinates() throws {
        // Orange in the top half of the picture (Vision y > 0.5), gray below.
        let pixels = bitmap { _, y in y > 0.5 ? (255, 140, 0) : (128, 128, 128) }
        let top = try sample(pixels, CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        let bottom = try sample(pixels, CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(top.colorFractions[.orange] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(bottom.colorFractions[.gray] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(AppearanceAnalyzer.colorScore(top, expected: [.orange, .white])), 1)
        XCTAssertEqual(try XCTUnwrap(AppearanceAnalyzer.colorScore(bottom, expected: [.orange])), 0)
    }

    func testTextureTellsShinyFromPatternedFromSmooth() throws {
        let region = CGRect(x: 0, y: 0, width: 1, height: 1)
        let smooth = try sample(bitmap { _, _ in (90, 90, 160) }, region)
        let glossy = try sample(bitmap { x, y in
            Int(x * 40) % 5 == 0 && Int(y * 40) % 5 == 0 ? (255, 255, 255) : (90, 90, 160)
        }, region)
        let patterned = try sample(bitmap { x, y in
            (Int(x * 40) + Int(y * 40)).isMultiple(of: 2) ? (30, 30, 30) : (200, 200, 200)
        }, region)
        let shinyScore = { (s: AppearanceSample) in AppearanceAnalyzer.textureScore(s, expected: [.shiny])! }
        let patternScore = { (s: AppearanceSample) in AppearanceAnalyzer.textureScore(s, expected: [.patterned])! }
        let smoothScore = { (s: AppearanceSample) in AppearanceAnalyzer.textureScore(s, expected: [.smooth])! }
        XCTAssertGreaterThan(shinyScore(glossy), 0.9)
        XCTAssertLessThan(shinyScore(smooth), 0.1)
        XCTAssertGreaterThan(patternScore(patterned), 0.9)
        XCTAssertGreaterThan(smoothScore(smooth), 0.9)
        XCTAssertLessThan(smoothScore(patterned), 0.1)
    }

    func testShapeAndSize() throws {
        // Portrait image, 3:4. A box 0.2 wide × 0.15 high in normalized units is square in pixels.
        let square = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.15)
        let stick = CGRect(x: 0.4, y: 0.2, width: 0.05, height: 0.4)
        let aspect = 3.0 / 4.0
        XCTAssertGreaterThan(try XCTUnwrap(AppearanceAnalyzer.shapeScore(square, imageAspect: aspect, expected: [.round])), 0.95)
        XCTAssertLessThan(try XCTUnwrap(AppearanceAnalyzer.shapeScore(square, imageAspect: aspect, expected: [.elongated])), 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(AppearanceAnalyzer.shapeScore(stick, imageAspect: aspect, expected: [.elongated])), 0.95)

        let speck = CGRect(x: 0.5, y: 0.5, width: 0.08, height: 0.06)
        let half = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        XCTAssertEqual(try XCTUnwrap(AppearanceAnalyzer.sizeScore(speck, expected: .tiny)), 1)
        XCTAssertEqual(try XCTUnwrap(AppearanceAnalyzer.sizeScore(half, expected: .tiny)), 0)
        XCTAssertEqual(try XCTUnwrap(AppearanceAnalyzer.sizeScore(half, expected: .large)), 1)
        XCTAssertNil(AppearanceAnalyzer.sizeScore(half, expected: nil))
    }

    /// Windows of the frame say nothing about the object's own size or shape.
    func testTilesAreScoredOnColorAndTextureOnly() throws {
        let sample = AppearanceSample(colorFractions: [.white: 1], gloss: 0, detail: 0)
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "pills"))
        let tile = CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1.0 / 3)
        let asTile = try XCTUnwrap(AppearanceAnalyzer.appearanceScore(sample, box: tile, kind: .tile,
                                                                      appearance: pills, imageAspect: 0.75))
        let asObject = try XCTUnwrap(AppearanceAnalyzer.appearanceScore(sample, box: tile, kind: .salient,
                                                                        appearance: pills, imageAspect: 0.75))
        XCTAssertEqual(asTile, 1, accuracy: 0.001)
        XCTAssertLessThan(asObject, asTile, "A third of the frame is far too big for pills")
    }

    func testClassifierAndAppearanceCombine() {
        XCTAssertEqual(AppearanceAnalyzer.score(classifierConfidence: 0.25, appearanceScore: 0.5, kind: .salient),
                       0.8, accuracy: 0.001)
        XCTAssertEqual(AppearanceAnalyzer.score(classifierConfidence: nil, appearanceScore: 0.5, kind: .detection),
                       0.6, accuracy: 0.001)
        XCTAssertEqual(AppearanceAnalyzer.score(classifierConfidence: nil, appearanceScore: nil, kind: .tile), 0)
    }
}

// MARK: - Confirming a match

final class AppearanceMatchTrackerTests: XCTestCase {
    private func region(_ x: CGFloat, score: Double, classified: Bool = true) -> ScoredRegion {
        ScoredRegion(box: CGRect(x: x, y: 0.4, width: 0.1, height: 0.1), kind: .salient,
                     classifierConfidence: classified ? 0.2 : nil, appearanceScore: 0.6, score: score)
    }

    func testNeedsTwoAgreeingPasses() {
        var tracker = AppearanceMatchTracker()
        XCTAssertNil(tracker.update(best: region(0.4, score: 0.8), at: 1))
        let match = tracker.update(best: region(0.42, score: 0.7), at: 1.4)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.classifierBacked, true)
    }

    func testDisagreeingPassesDoNotConfirm() {
        var tracker = AppearanceMatchTracker()
        XCTAssertNil(tracker.update(best: region(0.1, score: 0.8), at: 1))
        XCTAssertNil(tracker.update(best: region(0.7, score: 0.8), at: 1.4))
    }

    func testColorAloneNeedsAHigherScore() {
        var tracker = AppearanceMatchTracker()
        tracker.update(best: region(0.4, score: 0.6, classified: false), at: 1)
        XCTAssertNil(tracker.update(best: region(0.4, score: 0.6, classified: false), at: 1.4))
        tracker.update(best: region(0.4, score: 0.7, classified: false), at: 2)
        let match = tracker.update(best: region(0.4, score: 0.7, classified: false), at: 2.4)
        XCTAssertEqual(match?.classifierBacked, false)
    }

    /// A reaching hand hides the object from the classifier; the match holds, then expires.
    func testHoldsThroughShortGapsThenLetsGo() {
        var tracker = AppearanceMatchTracker()
        tracker.update(best: region(0.4, score: 0.8), at: 1)
        tracker.update(best: region(0.4, score: 0.8), at: 1.4)
        XCTAssertNotNil(tracker.update(best: nil, at: 3))
        XCTAssertNotNil(tracker.update(best: region(0.4, score: 0.2), at: 4))
        XCTAssertNil(tracker.update(best: nil, at: 4.5))
    }

    /// A grid window is a third of the screen; a hand must never be guided to its center.
    func testGridWindowsNeverBecomeTheMatch() {
        var tracker = AppearanceMatchTracker()
        let tile = ScoredRegion(box: AppearanceScanner.tiles[4], kind: .tile, classifierConfidence: 0.3,
                                appearanceScore: 0.9, score: 0.95)
        XCTAssertNil(tracker.update(best: tile, at: 1))
        XCTAssertNil(tracker.update(best: tile, at: 1.4))
        XCTAssertNil(tracker.update(best: tile, at: 1.8))
    }

    func testFollowsTheMatchAsItMoves() throws {
        var tracker = AppearanceMatchTracker()
        tracker.update(best: region(0.4, score: 0.8), at: 1)
        tracker.update(best: region(0.4, score: 0.8), at: 1.4)
        let moved = try XCTUnwrap(tracker.update(best: region(0.5, score: 0.8), at: 1.8))
        XCTAssertEqual(moved.box.minX, 0.45, accuracy: 0.001)
    }
}

// MARK: - Scanning a camera frame

final class AppearanceScannerTests: XCTestCase {
    /// Native landscape BGRA buffer: orange where the upright `box` maps in sensor space, gray elsewhere.
    private func pixelBuffer(orangeAtUpright box: CGRect, width: Int = 400, height: Int = 300) throws -> CVPixelBuffer {
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
        let sensor = DetectionGeometry.sensorRect(box)
        for row in 0..<height {
            for column in 0..<width {
                let inside = sensor.contains(CGPoint(x: (Double(column) + 0.5) / Double(width),
                                                     y: (Double(row) + 0.5) / Double(height)))
                let offset = row * rowBytes + column * 4
                // BGRA
                base[offset] = inside ? 0 : 128
                base[offset + 1] = inside ? 140 : 128
                base[offset + 2] = inside ? 255 : 128
                base[offset + 3] = 255
            }
        }
        return pixels
    }

    /// The region painted orange outscores an equally proposed gray one, so the frame's rotation into
    /// upright Vision coordinates matches the detector's.
    func testFindsTheRegionThatLooksRight() async throws {
        let target = CGRect(x: 0.15, y: 0.6, width: 0.2, height: 0.15)
        let decoy = CGRect(x: 0.6, y: 0.15, width: 0.2, height: 0.15)
        let buffer = try pixelBuffer(orangeAtUpright: target)
        let appearance = TargetAppearance(name: "lid", source: .words, colors: [.orange], shapes: [.round],
                                          size: .small)
        let regions = await AppearanceScanner().scan(pixelBuffer: buffer, appearance: appearance,
                                                     detections: [decoy, target])
        // Saliency may propose the same orange patch too; either way the best region is on it.
        let best = try XCTUnwrap(regions.first)
        XCTAssertTrue(target.insetBy(dx: -0.05, dy: -0.05).contains(CGPoint(x: best.box.midX, y: best.box.midY)))
        let detected = try XCTUnwrap(regions.first { $0.box == target })
        XCTAssertGreaterThan(detected.score, 0.9)
        let gray = try XCTUnwrap(regions.first { $0.box == decoy })
        XCTAssertLessThan(gray.score, 0.3, "Right size and shape, wrong color")
    }

    /// With classifier labels, the grid windows are searched too and the classifier runs on every region
    /// (or, where it can't run, the search carries on with color and texture).
    func testClassifierLabelsAddGridWindows() async throws {
        let buffer = try pixelBuffer(orangeAtUpright: CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1))
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "pills"))
        let regions = await AppearanceScanner().scan(pixelBuffer: buffer, appearance: pills, detections: [])
        XCTAssertGreaterThanOrEqual(regions.filter { $0.kind == .tile }.count, 9)
        XCTAssertTrue(regions.allSatisfy { (0...1).contains($0.score) })
    }

    func testSmallRegionsGetContextForTheClassifier() {
        let grown = AppearanceScanner.classifierRegion(for: CGRect(x: 0.95, y: 0.5, width: 0.04, height: 0.04))
        XCTAssertEqual(grown.height, AppearanceScanner.minimumClassifierRegion, accuracy: 0.0001)
        XCTAssertEqual(grown.maxX, 1, accuracy: 0.0001, "Clipped to the frame")
    }
}

// MARK: - What Locate says

final class AppearanceSearchPhrasesTests: XCTestCase {
    func testSearchLineSaysWhatItsLookingFor() throws {
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "pills"))
        XCTAssertEqual(AppearanceSearchPhrases.searching(for: pills),
                       "I don't have a detector trained for pills, so I'll look for it by sight, something tiny, "
                       + "round or elongated and white, yellow or orange. Move the camera slowly over where it might be.")
    }

    func testFoundLineIsHonestAboutColorOnlyMatches() {
        let sure = AppearanceMatch(box: CGRect(x: 0.45, y: 0.4, width: 0.1, height: 0.1), score: 0.8, lastSeen: 0,
                                   classifierBacked: true)
        let unsure = AppearanceMatch(box: CGRect(x: 0.05, y: 0.4, width: 0.1, height: 0.1), score: 0.8, lastSeen: 0,
                                     classifierBacked: false)
        XCTAssertTrue(AppearanceSearchPhrases.found("pills", match: sure).hasPrefix("I think I see the pills"))
        XCTAssertTrue(AppearanceSearchPhrases.found("keys", match: unsure).contains("check it by touch"))
    }

    func testHintSaysWhichWayToTurnTheCamera() {
        XCTAssertTrue(AppearanceSearchPhrases.hint("keys", box: AppearanceScanner.tiles[0]).contains("on your left, down low"))
        XCTAssertTrue(AppearanceSearchPhrases.hint("keys", box: AppearanceScanner.tiles[4]).contains("straight ahead"))
        XCTAssertTrue(AppearanceSearchPhrases.hint("keys", box: AppearanceScanner.tiles[8]).contains("on your right, up high"))
    }

    /// A name holding a "go back" word would be heard as the command when Iris said it.
    func testSpokenNamesDropGoBackWords() {
        let keywords = ["go back", "back", "return", "previous", "exit", "leave", "quit", "cancel"]
        XCTAssertEqual(AppearanceSearchPhrases.speakable("back brace", avoiding: keywords), "brace")
        XCTAssertEqual(AppearanceSearchPhrases.speakable("Exit sign", avoiding: keywords), "sign")
        XCTAssertEqual(AppearanceSearchPhrases.speakable("back", avoiding: keywords), "object")
        XCTAssertEqual(AppearanceSearchPhrases.speakable("pill bottle", avoiding: keywords), "pill bottle")
    }

    /// The microphone hears the speaker; Locate's back keywords would leave the screen.
    func testNoLineContainsAGoBackKeyword() throws {
        let keywords = ["back", "return", "previous", "exit", "leave", "quit", "cancel"]
        let pills = try XCTUnwrap(AppearanceCatalog.appearance(for: "pills"))
        let match = AppearanceMatch(box: .zero, score: 0.5, lastSeen: 0, classifierBacked: false)
        let lines = [AppearanceSearchPhrases.thinking(about: "stapler"), AppearanceSearchPhrases.searching(for: pills),
                     AppearanceSearchPhrases.found("pills", match: match), AppearanceSearchPhrases.unknown("thing")]
            + AppearanceScanner.tiles.map { AppearanceSearchPhrases.hint("pills", box: $0) }
        for line in lines {
            let words = line.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
            for keyword in keywords {
                XCTAssertFalse(words.contains(keyword), "\"\(keyword)\" in \(line)")
            }
        }
    }
}
