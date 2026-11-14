import CoreGraphics
import Foundation

/// A text line merged across several frames.
struct AccumulatedTextLine: Equatable, Sendable {
    var text: String
    var confidence: Double
    var seenCount: Int
    /// Average line height relative to the crop. Larger text is usually the product or drug name.
    var averageHeight: Double
    /// Average vertical center (bottom-left origin, so larger is higher on the label).
    var averageMidY: Double
    /// Order of first appearance, used to break ties.
    var firstSeenOrder: Int
}

/// Merges recognized lines from many frames. Curved labels are rarely readable in one frame:
/// as the item turns, different parts of each line come into view.
struct LabelTextAccumulator: Sendable {
    /// Lines are considered the same when their normalized edit distance is at most this fraction.
    var similarityThreshold = 0.2
    var maximumLines = 60

    private(set) var lines: [AccumulatedTextLine] = []
    private var nextOrder = 0

    var isEmpty: Bool { lines.isEmpty }

    /// Top-to-bottom reading order.
    var orderedLines: [AccumulatedTextLine] {
        lines.sorted { lhs, rhs in
            if abs(lhs.averageMidY - rhs.averageMidY) > 0.015 { return lhs.averageMidY > rhs.averageMidY }
            return lhs.firstSeenOrder < rhs.firstSeenOrder
        }
    }

    mutating func reset() {
        lines.removeAll()
        nextOrder = 0
    }

    mutating func add(_ recognized: [RecognizedTextLine]) {
        for line in recognized {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let key = Self.normalized(text)
            guard key.count >= 2 else { continue }

            if let index = matchIndex(for: key) {
                merge(text: text, key: key, line: line, into: index)
            } else if lines.count < maximumLines {
                lines.append(AccumulatedTextLine(text: text, confidence: line.confidence, seenCount: 1,
                                                 averageHeight: Double(line.boundingBox.height),
                                                 averageMidY: Double(line.boundingBox.midY),
                                                 firstSeenOrder: nextOrder))
                nextOrder += 1
            }
        }
    }

    private func matchIndex(for key: String) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, existing) in lines.enumerated() {
            let existingKey = Self.normalized(existing.text)
            // A fragment of a longer line (seen while the label was partly turned away).
            if min(key.count, existingKey.count) >= 4,
               existingKey.contains(key) || key.contains(existingKey) {
                return index
            }
            let longer = max(key.count, existingKey.count)
            guard Double(min(key.count, existingKey.count)) / Double(longer) >= 1 - similarityThreshold else {
                continue
            }
            let distance = Double(Self.editDistance(key, existingKey)) / Double(longer)
            if distance <= similarityThreshold, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    private mutating func merge(text: String, key: String, line: RecognizedTextLine, into index: Int) {
        var existing = lines[index]
        let existingKey = Self.normalized(existing.text)
        let count = Double(existing.seenCount)
        existing.averageHeight = (existing.averageHeight * count + Double(line.boundingBox.height)) / (count + 1)
        existing.averageMidY = (existing.averageMidY * count + Double(line.boundingBox.midY)) / (count + 1)
        existing.seenCount += 1

        // Prefer the more complete reading of a fragment, otherwise the more confident one.
        let isMoreComplete = key.count > existingKey.count && key.contains(existingKey)
        let isFragment = existingKey.count > key.count && existingKey.contains(key)
        if isMoreComplete || (!isFragment && line.confidence > existing.confidence) {
            existing.text = text
        }
        existing.confidence = max(existing.confidence, line.confidence)
        lines[index] = existing
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
