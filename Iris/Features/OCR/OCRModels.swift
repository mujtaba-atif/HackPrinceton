import CoreGraphics
import Foundation

/// One line of recognized text. `boundingBox` uses Vision coordinates in the upright portrait
/// image (normalized, bottom-left origin), the same convention as `DetectedObject.boundingBox`.
struct RecognizedTextLine: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let confidence: Double
    let boundingBox: CGRect

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.confidence == rhs.confidence && lhs.boundingBox == rhs.boundingBox
    }
}

struct OCRResult: Equatable, Sendable {
    let lines: [RecognizedTextLine]
    /// What was read, e.g. "bottle" when focused on a selected object, or nil for the center of the view.
    let focusName: String?
    let timestamp: TimeInterval

    var text: String { lines.map(\.text).joined(separator: "\n") }
    var meanConfidence: Double {
        lines.isEmpty ? 0 : lines.reduce(0) { $0 + $1.confidence } / Double(lines.count)
    }
    var isLowConfidence: Bool { meanConfidence < 0.5 }
    /// A ranking score used to keep the best of several frames: more confident text wins.
    var score: Double { lines.reduce(0) { $0 + $1.confidence * Double(min($1.text.count, 40)) } }
}

enum OCRState: Equatable, Sendable {
    case idle
    case reading
    case result(OCRResult)
    case noText(hint: String)
    case failed(message: String)

    var result: OCRResult? {
        if case let .result(result) = self { return result }
        return nil
    }
}

enum OCRGeometry {
    /// Centered region read when no object is selected (Vision coordinates).
    static let defaultRegion = CGRect(x: 0.15, y: 0.15, width: 0.7, height: 0.7)

    /// Expands an object's box by `margin` of its size on each side, then clips to the image.
    /// Labels often extend past a detector's tight box, so a little context improves recognition.
    static func focusRegion(for box: CGRect?, margin: CGFloat = 0.12) -> CGRect {
        guard let box, let clipped = DetectionGeometry.clippedUnitRect(box) else { return defaultRegion }
        let expanded = clipped.insetBy(dx: -clipped.width * margin, dy: -clipped.height * margin)
        guard let result = DetectionGeometry.clippedUnitRect(expanded),
              result.width >= 0.05, result.height >= 0.05 else { return defaultRegion }
        return result
    }

    /// Sorts lines top-to-bottom then left-to-right. Vision y grows upward, so higher midY reads first.
    /// Lines whose vertical centers are within `rowTolerance` count as the same row.
    static func readingOrder(_ lines: [RecognizedTextLine], rowTolerance: CGFloat = 0.02) -> [RecognizedTextLine] {
        lines.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) > rowTolerance {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }
    }
}
