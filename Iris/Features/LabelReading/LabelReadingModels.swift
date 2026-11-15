import CoreGraphics
import Foundation

/// One line of text recognized inside a label crop.
/// `boundingBox` is normalized to the **crop**, with a bottom-left origin (Vision convention).
struct RecognizedTextLine: Equatable, Sendable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}

/// The region of the upright camera image Iris reads from, and where the object sits inside it.
/// Both rectangles use Vision coordinates: normalized, bottom-left origin.
struct LabelCropPlan: Equatable, Sendable {
    /// Region of the full upright portrait image to crop.
    let cropRect: CGRect
    /// The object's own bounds expressed relative to `cropRect` (0...1). Edge and centering checks use this,
    /// so the padding around a bottle is never mistaken for the bottle's edge.
    let objectRegion: CGRect
    /// False when no detected object was available and the center of the frame is used instead.
    let usesDetectedObject: Bool
}

/// Measurements describing how much of a label faces the camera in one frame.
struct LabelReadiness: Equatable, Sendable {
    var lineCount = 0
    var characterCount = 0
    var meanConfidence = 0.0
    /// Fraction of the object region covered by text boxes.
    var textCoverage = 0.0
    /// Confidence-weighted horizontal center of the text, from -1 (object's left edge) to +1 (right edge).
    var horizontalCentroid: Double?
    /// Text touches the object's left edge, so the label continues around that side.
    var leftEdgeCut = false
    /// Text touches the object's right edge, so the label continues around that side.
    var rightEdgeCut = false
    /// Median line height relative to the object region's height.
    var medianTextHeight = 0.0

    static let empty = LabelReadiness()

    /// 0...1 estimate of how readable the label currently is. Drives the meter and cue tempo.
    var score: Double {
        guard lineCount > 0 else { return 0 }
        let characters = min(Double(characterCount) / 40, 1)
        let centering = 1 - min(abs(horizontalCentroid ?? 1), 1)
        let edges: Double = (leftEdgeCut != rightEdgeCut) ? 0.6 : 1
        let value = (0.4 * characters + 0.35 * centering + 0.25 * meanConfidence) * edges
        return min(max(value, 0), 1)
    }
}

/// What the user should do next.
enum LabelGuidanceDecision: Equatable, Sendable {
    /// No readable text on the object yet.
    case searching
    /// Label wraps around the object's right side: rotate so the front moves toward the user's left.
    case turnLeft
    /// Label wraps around the object's left side: rotate so the front moves toward the user's right.
    case turnRight
    /// Text is centered but too small to read.
    case moveCloser
    /// The image is too dark to find text.
    case needsLight
    /// Text is centered but recognition is weak (blur, glare, motion).
    case holdSteady
    /// Label faces the camera and is readable.
    case ready

    var isTurn: Bool { self == .turnLeft || self == .turnRight }

    var shortInstruction: String {
        switch self {
        case .searching: "Turn it slowly"
        case .turnLeft: "Turn left"
        case .turnRight: "Turn right"
        case .moveCloser: "Move it closer"
        case .needsLight: "Too dark"
        case .holdSteady: "Hold it steady"
        case .ready: "Hold still"
        }
    }

    var systemImage: String {
        switch self {
        case .searching: "arrow.triangle.2.circlepath"
        case .turnLeft: "arrow.counterclockwise"
        case .turnRight: "arrow.clockwise"
        case .moveCloser: "plus.magnifyingglass"
        case .needsLight: "lightbulb.fill"
        case .holdSteady: "hand.raised.fill"
        case .ready: "checkmark.circle.fill"
        }
    }
}

/// Speech-worthy moments produced by `LabelGuidanceStabilizer`.
enum LabelGuidanceEvent: Equatable, Sendable {
    case instruct(LabelGuidanceDecision)
    case encourage
    case wrongWay
    case trySweepOtherWay
    case noTextFound
}

enum LabelGuidanceFailure: Equatable, Sendable {
    case noTextFound
    case timedOut
    case cameraStopped
    case recognitionFailed(String)

    var title: String {
        switch self {
        case .noTextFound: "No readable text found"
        case .timedOut: "Couldn't get a clear view"
        case .cameraStopped: "Camera stopped"
        case .recognitionFailed: "Text recognition failed"
        }
    }

    var spokenMessage: String {
        switch self {
        case .noTextFound:
            "I couldn't find readable text on this item. Try turning it the other way, tilting it, or moving to better light."
        case .timedOut:
            "I couldn't get a clear view of the label. Try again in better light, and turn the item slowly."
        case .cameraStopped:
            "The camera stopped. Start the camera and try again."
        case let .recognitionFailed(message):
            "Text recognition failed. \(message)"
        }
    }
}

enum LabelGuidanceState: Equatable, Sendable {
    case idle
    case guiding(LabelGuidanceDecision)
    case capturing
    case interpreting
    case result
    case failed(LabelGuidanceFailure)

    var isActive: Bool {
        switch self {
        case .guiding, .capturing, .interpreting: true
        case .idle, .result, .failed: false
        }
    }
}

/// Structured fields read from a label. Every value is copied from recognized text; nothing is inferred.
struct LabelReading: Equatable, Sendable {
    var title: String?
    var titleIsUncertain = false
    var strength: String?
    var directions: String?
    var quantity: String?
    var refills: String?
    var rxNumber: String?
    var pharmacy: String?
    var prescriber: String?
    var dateFilled: String?
    var discardOrExpiration: String?
    var warnings: [String] = []
    var allLines: [String] = []
    var isLikelyPrescription = false

    var hasAnyText: Bool { !allLines.isEmpty }

    var hasMoreDetails: Bool {
        [rxNumber, quantity, refills, pharmacy, prescriber, dateFilled].contains { $0 != nil }
    }

    /// Important fields that were expected but not readable.
    var missingImportantFields: [String] {
        var missing: [String] = []
        if title == nil { missing.append(isLikelyPrescription ? "medication name" : "product name") }
        if isLikelyPrescription && directions == nil { missing.append("directions") }
        return missing
    }
}
