import SwiftUI

/// SVG path data (`d`) to a SwiftUI `Path`, in the SVG's own user units (y down).
///
/// Covers what the design's artwork uses: moveto, lineto, horizontal/vertical lineto, cubic and quadratic
/// Béziers with their smooth forms, and closepath, absolute and relative. An elliptical arc is drawn as a
/// straight line to its end point (the artwork has none).
enum SVGPath {
    static func parse(_ data: String) -> Path {
        var path = Path()
        var scanner = Tokens(data)
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// The last control point, for the smooth curve commands' reflection.
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?

        while let token = scanner.next() {
            switch token {
            case .command(let c):
                command = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    lastCubic = nil
                    lastQuad = nil
                    continue
                }
            case .number(let n):
                scanner.pushBack(n)
            }

            let relative = command.isLowercase
            func point(_ x: Double, _ y: Double) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch command.uppercased().first! {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
                // Pairs after a moveto are linetos.
                command = relative ? "l" : "L"
                lastCubic = nil
                lastQuad = nil
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
                lastCubic = nil
                lastQuad = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubic = nil
                lastQuad = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubic = nil
                lastQuad = nil
            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = point(x1, y1), c2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubic = c2
                lastQuad = nil
            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubic = c2
                lastQuad = nil
            case "Q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let c = point(x1, y1), end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuad = c
                lastCubic = nil
            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuad = c
                lastCubic = nil
            case "A":
                guard scanner.number() != nil, scanner.number() != nil, scanner.number() != nil,
                      scanner.number() != nil, scanner.number() != nil,
                      let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
                lastCubic = nil
                lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    private enum Token {
        case command(Character)
        case number(Double)
    }

    /// Splits path data into commands and numbers, including the compact forms ("M-60-40", "1.5.5").
    private struct Tokens {
        private let chars: [Character]
        private var index = 0
        private var pending: Double?

        init(_ text: String) { chars = Array(text) }

        mutating func pushBack(_ number: Double) { pending = number }

        mutating func next() -> Token? {
            if let pending {
                self.pending = nil
                return .number(pending)
            }
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter, c != "e", c != "E" {
                index += 1
                return .command(c)
            }
            return readNumber().map { .number($0) }
        }

        mutating func number() -> Double? {
            if let pending {
                self.pending = nil
                return pending
            }
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            guard c.isNumber || c == "-" || c == "+" || c == "." else { return nil }
            return readNumber()
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline || chars[index] == "\t" {
                index += 1
            }
        }

        private mutating func readNumber() -> Double? {
            var text = ""
            var seenDot = false, seenExponent = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                text.append(chars[index])
                index += 1
            }
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    text.append(c)
                } else if c == ".", !seenDot, !seenExponent {
                    seenDot = true
                    text.append(c)
                } else if c == "e" || c == "E", !seenExponent {
                    seenExponent = true
                    text.append(c)
                    if index + 1 < chars.count, chars[index + 1] == "-" || chars[index + 1] == "+" {
                        index += 1
                        text.append(chars[index])
                    }
                } else {
                    break
                }
                index += 1
            }
            return Double(text)
        }
    }
}
