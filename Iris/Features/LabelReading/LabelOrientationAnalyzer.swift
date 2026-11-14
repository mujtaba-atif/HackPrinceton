import CoreGraphics
import Foundation

/// Decides which way a held item should turn so its label faces the camera.
///
/// On a cylinder (a pill bottle, can, or jar), a label facing away shows up as text crowded against one
/// silhouette edge, often cut off there. Iris's convention: text on the object's **right** side means
/// "turn left" (the front surface moves toward the user's left, bringing the right side forward).
/// Pure value logic so it can be unit tested without a camera.
struct LabelOrientationAnalyzer: Sendable {
    struct Configuration: Sendable {
        /// Fraction of the object's width treated as its edge.
        var edgeMargin = 0.08
        /// |centroid| at or below this counts as centered.
        var centerTolerance = 0.25
        /// With text cut off at one edge, a lean toward that edge beyond this triggers a turn.
        var edgeLeanThreshold = 0.05
        /// Lines below this confidence are ignored.
        var minimumLineConfidence = 0.3
        /// Mean confidence needed before reading.
        var readyConfidence = 0.5
        /// Characters needed before reading.
        var readyCharacters = 12
        /// Median line height (relative to the object's height) below which the user should move closer.
        var minimumTextHeight = 0.03
        /// Average luminance (0...1) below which the scene is too dark when no text is found.
        var darkLuminance = 0.12
        /// Measured distance beyond which small amounts of text suggest moving closer.
        var farDistanceMeters = 0.7
    }

    var configuration = Configuration()

    /// Lines that look like real text rather than noise.
    func usableLines(_ lines: [RecognizedTextLine]) -> [RecognizedTextLine] {
        lines.filter { line in
            line.confidence >= configuration.minimumLineConfidence
                && line.text.filter { $0.isLetter || $0.isNumber }.count >= 2
                && line.boundingBox.width > 0 && line.boundingBox.height > 0
        }
    }

    func readiness(for lines: [RecognizedTextLine], objectRegion: CGRect) -> LabelReadiness {
        let usable = usableLines(lines)
        guard !usable.isEmpty, objectRegion.width > 0, objectRegion.height > 0 else { return .empty }

        var readiness = LabelReadiness()
        readiness.lineCount = usable.count
        readiness.characterCount = usable.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
        readiness.meanConfidence = usable.reduce(0) { $0 + $1.confidence } / Double(usable.count)

        var weightedX = 0.0
        var totalWeight = 0.0
        var coveredArea = 0.0
        var heights: [Double] = []
        let leftEdge = objectRegion.minX + configuration.edgeMargin * objectRegion.width
        let rightEdge = objectRegion.maxX - configuration.edgeMargin * objectRegion.width

        for line in usable {
            let box = line.boundingBox
            // Position relative to the object: -1 at its left edge, +1 at its right edge.
            let relativeX = ((box.midX - objectRegion.minX) / objectRegion.width) * 2 - 1
            let weight = line.confidence * Double(max(box.width, 0.01))
            weightedX += relativeX * weight
            totalWeight += weight
            coveredArea += Double(box.width * box.height)
            heights.append(Double(box.height / objectRegion.height))
            if box.minX <= leftEdge { readiness.leftEdgeCut = true }
            if box.maxX >= rightEdge { readiness.rightEdgeCut = true }
        }

        readiness.horizontalCentroid = totalWeight > 0 ? min(max(weightedX / totalWeight, -1), 1) : nil
        readiness.textCoverage = min(coveredArea / Double(objectRegion.width * objectRegion.height), 1)
        heights.sort()
        readiness.medianTextHeight = heights[heights.count / 2]
        return readiness
    }

    func decide(_ readiness: LabelReadiness, luminance: Double?, distanceMeters: Double?) -> LabelGuidanceDecision {
        guard readiness.lineCount > 0, let centroid = readiness.horizontalCentroid else {
            if let luminance, luminance < configuration.darkLuminance { return .needsLight }
            return .searching
        }

        // A label spanning both edges faces the camera. Text cut off at one edge, and leaning toward it,
        // means the label wraps away on that side.
        if readiness.rightEdgeCut && !readiness.leftEdgeCut && centroid > configuration.edgeLeanThreshold {
            return .turnLeft
        }
        if readiness.leftEdgeCut && !readiness.rightEdgeCut && centroid < -configuration.edgeLeanThreshold {
            return .turnRight
        }
        if centroid > configuration.centerTolerance { return .turnLeft }
        if centroid < -configuration.centerTolerance { return .turnRight }

        let isReadable = readiness.meanConfidence >= configuration.readyConfidence
            && readiness.characterCount >= configuration.readyCharacters
        if readiness.medianTextHeight < configuration.minimumTextHeight && !isReadable {
            return .moveCloser
        }
        if let distanceMeters, distanceMeters > configuration.farDistanceMeters && !isReadable {
            return .moveCloser
        }
        return isReadable ? .ready : .holdSteady
    }

    func analyze(_ lines: [RecognizedTextLine], objectRegion: CGRect,
                 luminance: Double?, distanceMeters: Double?) -> (LabelReadiness, LabelGuidanceDecision) {
        let readiness = readiness(for: lines, objectRegion: objectRegion)
        return (readiness, decide(readiness, luminance: luminance, distanceMeters: distanceMeters))
    }
}

/// Chooses which part of the upright camera image to read.
enum LabelCropPlanner {
    /// Used when nothing is selected or detected: most items held up to read sit near the center.
    static let centerRegion = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    /// - Parameter objectBox: Vision-normalized upright box of the item, if one is known.
    /// - Parameter padding: Extra margin on each side, as a fraction of the box size.
    static func plan(objectBox: CGRect?, padding: CGFloat = 0.12) -> LabelCropPlan {
        guard let box = objectBox.flatMap(DetectionGeometry.clippedUnitRect),
              box.width >= 0.02, box.height >= 0.02 else {
            return LabelCropPlan(cropRect: centerRegion,
                                 objectRegion: CGRect(x: 0, y: 0, width: 1, height: 1),
                                 usesDetectedObject: false)
        }
        let expanded = box.insetBy(dx: -box.width * padding, dy: -box.height * padding)
        let crop = expanded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let objectRegion = CGRect(x: (box.minX - crop.minX) / crop.width,
                                  y: (box.minY - crop.minY) / crop.height,
                                  width: box.width / crop.width,
                                  height: box.height / crop.height)
        return LabelCropPlan(cropRect: crop, objectRegion: objectRegion, usesDetectedObject: true)
    }
}
