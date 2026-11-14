import Foundation

/// A quick, silent read of whatever label is in view, merged across a few frames.
/// Used by the assistant's `read_label` tool and as a fallback, where spoken turn guidance
/// (`LabelGuidanceService`) would talk over the conversation.
struct OCRResult: Equatable, Sendable {
    /// Merged lines in reading order (top to bottom).
    let lines: [AccumulatedTextLine]
    /// What was read, e.g. "bottle" when focused on a selected object, or nil for the center of the view.
    let focusName: String?
    let timestamp: TimeInterval

    var text: String { lines.map(\.text).joined(separator: "\n") }
    var meanConfidence: Double {
        lines.isEmpty ? 0 : lines.reduce(0) { $0 + $1.confidence } / Double(lines.count)
    }
    var isLowConfidence: Bool { meanConfidence < 0.5 }
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
