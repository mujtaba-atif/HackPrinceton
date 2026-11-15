import SwiftUI
import XCTest
@testable import Iris

/// The view-free parts of the Iris design port: SVG parsing, CSS timing, the stage, mask contours and the
/// guidance waves.
final class IrisDesignTests: XCTestCase {

    // MARK: SVG

    func testPathParsesCompactAndRelativeCommands() {
        // "M-60-40H540V105" packs signs as separators; "m3 15 12-12 12 12" is relative.
        let wave = SVGPath.parse("M-60-40H540V105Z").boundingRect
        XCTAssertEqual(wave.minX, -60, accuracy: 0.001)
        XCTAssertEqual(wave.minY, -40, accuracy: 0.001)
        XCTAssertEqual(wave.maxX, 540, accuracy: 0.001)
        XCTAssertEqual(wave.maxY, 105, accuracy: 0.001)

        let chevron = SVGPath.parse("m3 15 12-12 12 12").boundingRect
        XCTAssertEqual(chevron, CGRect(x: 3, y: 3, width: 24, height: 12))

        let dots = SVGPath.parse("M1.5.5L2.5.5").boundingRect
        XCTAssertEqual(dots.minX, 1.5, accuracy: 0.001)
        XCTAssertEqual(dots.maxX, 2.5, accuracy: 0.001)
        XCTAssertEqual(dots.minY, 0.5, accuracy: 0.001)
    }

    func testEveryArtworkParsesWithItsAnimatedGroups() {
        let card = IrisArtwork.locateCard
        XCTAssertEqual(card.viewBox, CGRect(x: 0, y: 0, width: 305, height: 177))
        XCTAssertFalse(card.root.flattenedShapes.isEmpty)
        XCTAssertEqual(IrisArtwork.revision, 18)
        XCTAssertEqual(IrisArtwork.locatePanel.viewBox.size, CGSize(width: 360, height: 448))
        XCTAssertEqual(IrisArtwork.explorePanel.viewBox.size, CGSize(width: 360, height: 448))
        XCTAssertNotNil(IrisArtwork.treasureMap.group("mapCompassNeedle"))
        XCTAssertNotNil(IrisArtwork.treasureMap.group("mapCourier"))
        XCTAssertNotNil(IrisArtwork.treasureMap.group("mapX"))
        XCTAssertNotNil(IrisArtwork.edgeLights.group("edgeRayL1"))
        XCTAssertNotNil(IrisArtwork.edgeLights.group("edgeRayR2"))

        for hero in [IrisArtwork.skye, IrisArtwork.pip, IrisArtwork.nova, IrisArtwork.echo] {
            XCTAssertEqual(hero.viewBox.size, CGSize(width: 120, height: 150))
            let eyes = try! XCTUnwrap(hero.group("mini-eyes"))
            XCTAssertNotNil(eyes.find("mini-gaze"), "the gaze moves inside the blinking eyes")
            XCTAssertFalse(hero.outline.isEmpty)
        }
        XCTAssertFalse(IrisArtwork.exploreCard.root.flattenedShapes.isEmpty)
    }

    func testSplitPanelsHaveNoDeadZoneOrOverlappingTapRegion() {
        let rect = CGRect(x: 0, y: 0, width: 360, height: 800)
        let locate = DiscoverySplit(explore: false).path(in: rect)
        let explore = DiscoverySplit(explore: true).path(in: rect)
        for x in stride(from: 5.0, to: 360, by: 10) {
            let boundary = 448 - x * 96 / 360
            XCTAssertTrue(locate.contains(CGPoint(x: x, y: boundary - 1)))
            XCTAssertFalse(explore.contains(CGPoint(x: x, y: boundary - 1)))
            XCTAssertTrue(explore.contains(CGPoint(x: x, y: boundary + 1)))
            XCTAssertFalse(locate.contains(CGPoint(x: x, y: boundary + 1)))
        }
    }

    func testReadingRequiresRecognitionEvidenceAndRecoversFromLostText() {
        var readiness = RecognitionReadiness()
        XCTAssertEqual(readiness.update(hasVisibleText: false, consolidated: []), .searching)
        XCTAssertEqual(readiness.update(hasVisibleText: true, consolidated: []), .reading)
        XCTAssertEqual(readiness.update(hasVisibleText: true, consolidated: ["Water"]), .reading)
        XCTAssertEqual(readiness.update(hasVisibleText: true, consolidated: ["Water", "500 ml"]), .reading)
        XCTAssertEqual(readiness.update(hasVisibleText: true, consolidated: ["Water", "500 ml"]), .ready)
        XCTAssertEqual(readiness.update(hasVisibleText: false, consolidated: ["Water", "500 ml"]), .searching)
        XCTAssertEqual(readiness.update(hasVisibleText: true, consolidated: ["Water", "500 ml"]), .reading)
    }

    func testVectorTransformsAndDashPatternsPreserveDesignGeometry() {
        let art = VectorArt(svg: ##"<svg viewBox="0 0 100 100"><g transform="translate(20 10)"><path d="M0 0L10 0L10 10Z" fill="none" stroke="#FFFFFF" stroke-dasharray="3 4"/></g></svg>"##)
        let shape = art.root.flattenedShapes[0]
        XCTAssertEqual(shape.path.boundingRect, CGRect(x: 20, y: 10, width: 10, height: 10))
        XCTAssertEqual(shape.strokeStyle.dash, [3, 4])
    }

    func testColorsParse() {
        XCTAssertNotNil(parseColor("#FAFCFF"))
        XCTAssertNotNil(parseColor("#FAFCFF66"))
        XCTAssertNil(parseColor("none"))
        XCTAssertNil(parseColor("url(#x)"))
    }

    // MARK: CSS timing

    func testBezierMatchesKnownPoints() {
        XCTAssertEqual(Bezier.linear(0.3), 0.3, accuracy: 1e-4)
        XCTAssertEqual(Bezier.easeInOut(0.5), 0.5, accuracy: 1e-4)
        XCTAssertEqual(Bezier.ease(0), 0)
        XCTAssertEqual(Bezier.ease(1), 1)
        // The springs overshoot: (.2, .75, .2, 1.14) passes 1 before settling.
        let spring = Bezier(0.2, 0.75, 0.2, 1.14)
        XCTAssertGreaterThan((0..<100).map { spring(Double($0) / 100) }.max()!, 1)
    }

    func testMotionHoldsBeforeItsDelayAndSettlesAfter() {
        let rise = Motion(1, delay: 0.5, curve: .linear, from: Pose(y: 100, opacity: 0))
        XCTAssertEqual(rise.pose(at: 0).y, 100)
        XCTAssertEqual(rise.pose(at: 0).opacity, 0)
        XCTAssertEqual(rise.pose(at: 1).y, 50, accuracy: 1e-6)
        XCTAssertEqual(rise.pose(at: 5), .rest)
        XCTAssertEqual(rise.end, 1.5)
    }

    func testAlternatingLoopGoesBackAndForth() {
        let sway = Motion(2, curve: .linear, repeats: true, alternate: true, from: Pose(x: -10), to: Pose(x: 10))
        XCTAssertEqual(sway.pose(at: 1).x, 0, accuracy: 1e-6)
        XCTAssertEqual(sway.pose(at: 2).x, 10, accuracy: 1e-6)
        XCTAssertEqual(sway.pose(at: 3).x, 0, accuracy: 1e-6, "on the way back")
        XCTAssertEqual(sway.pose(at: 3.5).x, -5, accuracy: 1e-6)
        XCTAssertNil(sway.end)
        XCTAssertEqual(sway.settled, .rest, "loops stop dead under reduced motion")
    }

    func testMultiKeyframeBlinkClosesOnlyBriefly() {
        let blink = Motion(7.8, repeats: true, [
            (0, .rest), (0.63, .rest), (0.65, Pose(scaleX: 1, scaleY: 0.08)), (0.67, .rest), (1, .rest),
        ])
        XCTAssertEqual(blink.pose(at: 1).scaleY, 1)
        XCTAssertEqual(blink.pose(at: 7.8 * 0.65).scaleY, 0.08, accuracy: 1e-6)
        XCTAssertEqual(blink.pose(at: 7.8 * 0.8).scaleY, 1)
    }

    // MARK: Stage

    func testStageFitsTheDesignPhoneAndCentresIt() {
        let stage = Stage(size: CGSize(width: 428, height: 926))
        XCTAssertEqual(stage.unit, 926.0 / 800, accuracy: 1e-6)
        let full = stage.rect(CGRect(origin: .zero, size: Stage.design))
        XCTAssertEqual(full.midX, 214, accuracy: 1e-6)
        XCTAssertEqual(full.minY, 0, accuracy: 1e-6)
        XCTAssertEqual(full.height, 926, accuracy: 1e-6)
    }

    func testCSSGradientAngles() {
        let (start, end) = CSSLinearGradient.points(angle: 180, size: CGSize(width: 100, height: 200))
        XCTAssertEqual(start.y, 0, accuracy: 1e-6)
        XCTAssertEqual(end.y, 1, accuracy: 1e-6)
        XCTAssertEqual(start.x, 0.5, accuracy: 1e-6)
        let (from, to) = CSSLinearGradient.points(angle: 90, size: CGSize(width: 100, height: 200))
        XCTAssertEqual(from.x, 0, accuracy: 1e-6)
        XCTAssertEqual(to.x, 1, accuracy: 1e-6)
    }

    // MARK: Mask contour

    func testTraceWalksASquareInOrder() {
        // A 3 × 3 block in a 5 × 5 mask: its outer ring is 8 cells.
        var pixels = [Bool](repeating: false, count: 25)
        for y in 1...3 { for x in 1...3 { pixels[y * 5 + x] = true } }
        let loop = MaskContour.trace(width: 5, height: 5, pixels: pixels)
        XCTAssertEqual(loop.count, 8)
        XCTAssertEqual(loop.first?.x, 1)
        XCTAssertEqual(loop.first?.y, 1)
        // Each step is to a neighbouring cell.
        for (a, b) in zip(loop, loop.dropFirst() + [loop[0]]) {
            XCTAssertLessThanOrEqual(max(abs(a.x - b.x), abs(a.y - b.y)), 1)
        }
        XCTAssertFalse(loop.contains { $0.x == 2 && $0.y == 2 }, "the middle is not on the outline")
    }

    func testOutlineIsNormalizedAndSmooth() {
        var pixels = [Bool](repeating: false, count: 20 * 40)
        for y in 5..<35 { for x in 4..<16 { pixels[y * 20 + x] = true } }
        let outline = try! XCTUnwrap(MaskContour.outline(width: 20, height: 40, pixels: pixels))
        XCTAssertGreaterThan(outline.count, 8)
        for point in outline {
            XCTAssertTrue((0.15...0.85).contains(point.x))
            XCTAssertTrue((0.1...0.9).contains(point.y), "top-left origin, y down")
        }
        XCTAssertNil(MaskContour.outline(width: 4, height: 4, pixels: [Bool](repeating: false, count: 16)))
    }

    func testAspectFillMatchesTheCameraPreviewCrop() {
        // A 3:4 image on a taller screen is cropped at the sides.
        let image = CGSize(width: 1440, height: 1920), view = CGSize(width: 390, height: 844)
        let middle = MaskContour.aspectFill(CGPoint(x: 0.5, y: 0.5), image: image, view: view)
        XCTAssertEqual(middle.x, 195, accuracy: 1e-6)
        XCTAssertEqual(middle.y, 422, accuracy: 1e-6)
        let top = MaskContour.aspectFill(CGPoint(x: 0, y: 0), image: image, view: view)
        XCTAssertEqual(top.y, 0, accuracy: 1e-6)
        XCTAssertLessThan(top.x, 0, "the left edge is off screen")
    }

    // MARK: Guidance waves

    func testProximityPulsesBecomeFasterAndStrongerNearObject() throws {
        var cadence = ProximityHapticCadence()
        let far = try XCTUnwrap(cadence.pulse(distance: 0.5, timestamp: 10, now: 10))
        XCTAssertNil(cadence.pulse(distance: 0.5, timestamp: 10.5, now: 10.5))
        XCTAssertNotNil(cadence.pulse(distance: 0.5, timestamp: 11.3, now: 11.3))
        let near = try XCTUnwrap(cadence.pulse(distance: 0.02, timestamp: 11.6, now: 11.6))
        XCTAssertGreaterThan(near, far)
        XCTAssertNil(cadence.pulse(distance: 0.02, timestamp: 11.7, now: 11.7))
        XCTAssertNotNil(cadence.pulse(distance: 0.02, timestamp: 11.9, now: 11.9))
    }

    func testProximityRequiresValidFreshMetricDistance() {
        let invalidDistances: [Float?] = [nil, -.infinity, .infinity, .nan, -0.1, 0.51]
        for distance in invalidDistances {
            var cadence = ProximityHapticCadence()
            XCTAssertNil(cadence.pulse(distance: distance, timestamp: 10, now: 10))
        }
        var cadence = ProximityHapticCadence()
        XCTAssertNil(cadence.pulse(distance: 0.1, timestamp: 10, now: 11))
        XCTAssertNil(cadence.pulse(distance: 0.1, timestamp: 12, now: 11))
        XCTAssertNil(cadence.pulse(distance: 0.1, timestamp: .nan, now: 11))
        XCTAssertNotNil(cadence.pulse(distance: 0.1, timestamp: 11, now: 11))
        XCTAssertNil(cadence.pulse(distance: 0.1, timestamp: 11, now: 11.3), "Republishing one sample cannot vibrate twice")
        XCTAssertNil(cadence.pulse(distance: 0.1, timestamp: 10.9, now: 11.1), "Reject out-of-order results")
    }

    func testProximityDropoutDoesNotCauseBurstAndResetStartsNewSession() {
        var cadence = ProximityHapticCadence()
        XCTAssertNotNil(cadence.pulse(distance: 0, timestamp: 10, now: 10))
        XCTAssertNil(cadence.pulse(distance: nil, timestamp: 10.05, now: 10.05))
        XCTAssertNil(cadence.pulse(distance: 0, timestamp: 10.1, now: 10.1))
        XCTAssertNotNil(cadence.pulse(distance: 0, timestamp: 10.3, now: 10.3))
        cadence.reset()
        XCTAssertNotNil(cadence.pulse(distance: 0.5, timestamp: 10.4, now: 10.4))
    }

    func testSurgeSwellsAndEbbsEachPeriod() {
        XCTAssertEqual(CameraGlass.swell(0), 0, accuracy: 1e-6)
        XCTAssertEqual(CameraGlass.swell(0.35), 1, accuracy: 1e-6)
        XCTAssertEqual(CameraGlass.swell(0.999), 0, accuracy: 0.01)
        XCTAssertEqual(CameraGlass.swell(1.35), 1, accuracy: 1e-6, "every period")
    }

    // MARK: Explore without the agent

    func testExploreReadsTheLabelItselfWhenTheAgentIsGone() {
        let said = ExploreScreen.fallbackSummary(for: ["Oat Milk", "1 Litre", "Best before 12 May"])
        XCTAssertTrue(said.contains("Oat Milk. 1 Litre. Best before 12 May."))
        let many = ExploreScreen.fallbackSummary(for: (1...10).map { "Line \($0)" })
        XCTAssertFalse(many.contains("Line 7"), "at most six lines")
        XCTAssertTrue(ExploreScreen.fallbackSummary(for: []).contains("go back"), "and says how to leave")
    }
}
