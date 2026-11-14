import Foundation

/// Turns merged label text into structured fields.
/// Implementations must copy values from the text only, never fill gaps from general knowledge.
/// An AI-backed interpreter can conform later and fall back to `OfflineLabelInterpreter`.
protocol LabelInterpreting: Sendable {
    func interpret(_ lines: [AccumulatedTextLine]) async -> LabelReading
}

/// Rule-based interpreter that works without a network connection or API key.
struct OfflineLabelInterpreter: LabelInterpreting {
    func interpret(_ lines: [AccumulatedTextLine]) async -> LabelReading {
        read(lines)
    }

    func read(_ lines: [AccumulatedTextLine]) -> LabelReading {
        var reading = LabelReading()
        let texts = lines.map(\.text)
        reading.allLines = texts
        guard !texts.isEmpty else { return reading }

        let lowered = texts.map { $0.lowercased() }
        let keywordHits = Self.prescriptionKeywords.filter { keyword in lowered.contains { $0.contains(keyword) } }
        reading.isLikelyPrescription = texts.contains { Self.firstMatch(Self.rxMarker, in: $0) != nil }
            || keywordHits.count >= 2

        reading.directions = directions(in: texts)
        reading.rxNumber = texts.lazy.compactMap { Self.capture(Self.rxNumber, in: $0) }
            .first { $0.contains(where: \.isNumber) }
        reading.quantity = texts.lazy.compactMap { Self.capture(Self.quantity, in: $0) }.first
        reading.refills = refills(in: texts)
        reading.prescriber = texts.lazy.compactMap { Self.capture(Self.prescriber, in: $0) }.first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
        reading.pharmacy = texts.first { line in
            let lower = line.lowercased()
            return lower.contains("pharmacy") || lower.contains("drug store") || lower.contains("drugstore")
        }
        assignDates(from: texts, to: &reading)
        reading.warnings = Array(texts.filter { line in
            let lower = line.lowercased()
            return line != reading.directions && Self.warningKeywords.contains { lower.contains($0) }
        }.prefix(3))

        let (title, titleLine) = self.title(in: lines, reading: reading)
        reading.title = title
        reading.titleIsUncertain = (titleLine?.confidence ?? 1) < 0.6
        reading.strength = (titleLine.flatMap { Self.firstMatch(Self.strength, in: $0.text) })
            ?? texts.lazy.compactMap { Self.firstMatch(Self.strength, in: $0) }.first
        return reading
    }

    // MARK: Fields

    private func title(in lines: [AccumulatedTextLine],
                       reading: LabelReading) -> (String?, AccumulatedTextLine?) {
        // Prescription labels usually print the patient's name large, so never pick by size alone:
        // the drug name is the line that carries a strength ("METFORMIN HCL 500 MG").
        if reading.isLikelyPrescription {
            let line = lines.first { line in
                guard let strength = Self.firstMatch(Self.strength, in: line.text) else { return false }
                let remainder = line.text.replacingOccurrences(of: strength, with: "")
                return remainder.filter(\.isLetter).count >= 3
            }
            return (line?.text, line)
        }
        let candidates = lines.filter { line in
            line.text.filter(\.isLetter).count >= 3 && !isFieldLine(line.text, reading: reading)
        }
        let line = candidates.max { lhs, rhs in
            if abs(lhs.averageHeight - rhs.averageHeight) > 0.005 { return lhs.averageHeight < rhs.averageHeight }
            return lhs.confidence < rhs.confidence
        }
        return (line?.text, line)
    }

    private func isFieldLine(_ text: String, reading: LabelReading) -> Bool {
        let lower = text.lowercased()
        return text == reading.directions
            || reading.warnings.contains(text)
            || Self.firstMatch(Self.rxMarker, in: text) != nil
            || Self.capture(Self.quantity, in: text) != nil
            || lower.contains("refill")
            || Self.dateKeywords.contains { lower.contains($0) }
    }

    private func directions(in texts: [String]) -> String? {
        guard let index = texts.firstIndex(where: { line in
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            return Self.directionVerbs.contains { lower.hasPrefix($0 + " ") }
        }) else { return nil }
        var result = texts[index]
        let next = index + 1
        if !result.hasSuffix("."), next < texts.count {
            let candidate = texts[next]
            let lower = candidate.lowercased()
            let isOtherField = Self.firstMatch(Self.rxMarker, in: candidate) != nil
                || Self.capture(Self.quantity, in: candidate) != nil
                || lower.contains("refill")
                || Self.dateKeywords.contains { lower.contains($0) }
                || Self.warningKeywords.contains { lower.contains($0) }
                || Self.firstMatch(Self.strength, in: candidate) != nil
            if !isOtherField { result += " " + candidate }
        }
        return result
    }

    private func refills(in texts: [String]) -> String? {
        for text in texts {
            if text.range(of: #"(?i)\bno\s+refills?\b"#, options: .regularExpression) != nil { return "No refills" }
            if let value = Self.capture(Self.refillCount, in: text) {
                let lower = value.lowercased()
                return ["no", "none", "zero", "0"].contains(lower) ? "No refills" : "\(value) refills"
            }
        }
        return nil
    }

    private func assignDates(from texts: [String], to reading: inout LabelReading) {
        for text in texts {
            let lower = text.lowercased()
            let isExpiration = Self.expirationKeywords.contains { lower.contains($0) }
            let isFilled = !isExpiration && Self.filledKeywords.contains { lower.contains($0) }
            guard isExpiration || isFilled, let date = Self.spokenDate(in: text) else { continue }
            if isExpiration, reading.discardOrExpiration == nil { reading.discardOrExpiration = date }
            if isFilled, reading.dateFilled == nil { reading.dateFilled = date }
        }
    }

    // MARK: Patterns

    static let prescriptionKeywords = ["refill", "qty", "quantity", "tablet", "capsule", "pharmacy",
                                       "prescriber", "dr.", "by mouth", "discard", "take "]
    static let directionVerbs = ["take", "apply", "use", "inhale", "instill", "insert", "place", "dissolve",
                                 "chew", "give", "spray", "swallow", "shake", "mix"]
    static let warningKeywords = ["do not", "may cause", "caution", "warning", "avoid", "keep out of reach",
                                  "for external use", "harmful", "danger", "poison", "flammable"]
    static let expirationKeywords = ["discard", "exp", "use by", "use before", "best by", "best before", "bb:"]
    static let filledKeywords = ["fill", "dispensed", "date:"]
    static var dateKeywords: [String] { expirationKeywords + filledKeywords }

    static let rxMarker = #"(?i)\bRx\b"#
    static let strength = #"(?i)\b\d+(?:[.,]\d+)?\s?(?:mg|mcg|µg|g|ml|iu|units?|%)(?![a-z])"#
    static let rxNumber = #"(?i)\bRx\s*(?:No\.?|Number|#)?\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{3,})"#
    static let quantity = #"(?i)\b(?:Qty|Quantity)\.?\s*[:#]?\s*(\d+)"#
    static let refillCount = #"(?i)\b(?:Refills?|RF)\s*(?:left|remaining)?\s*[:#]?\s*(\d+|no|none|zero)\b"#
    static let prescriber = #"\b(?i:Prescriber|Prescribed by|Dr)\b\.?\s*:?\s*([A-Z][A-Za-z.'\- ]{2,40})"#
    static let numericDate = #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b|\b\d{1,2}[/-]\d{4}\b"#

    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func spokenDate(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        if let match = dateDetector?.firstMatch(in: text, options: [], range: range), let date = match.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return firstMatch(numericDate, in: text)
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// Builds what Iris says about a label: most important first, short, and never a safety verdict.
enum LabelReadingSpeech {
    static func summary(_ reading: LabelReading) -> String {
        guard reading.hasAnyText else {
            return "I couldn't read any text. Try turning it slightly or bringing it closer."
        }
        var parts: [String] = []
        if let title = reading.title {
            parts.append(reading.titleIsUncertain ? "I think this says \(title), but I'm not sure." : sentence(title))
        }
        if let strength = reading.strength,
           !(reading.title?.localizedCaseInsensitiveContains(strength) ?? false) {
            parts.append("Strength: \(strength).")
        }
        if let directions = reading.directions {
            parts.append(sentence(directions))
        }
        if let date = reading.discardOrExpiration {
            parts.append(reading.isLikelyPrescription ? "Discard after \(date)." : "Date on label: \(date).")
        }
        if let warning = reading.warnings.first {
            parts.append("Warning: \(sentence(warning))")
            if reading.warnings.count > 1 {
                parts.append("There are more warnings in Read Everything.")
            }
        }
        if !reading.isLikelyPrescription, parts.count <= 1,
           let extra = reading.allLines.first(where: { $0 != reading.title }) {
            parts.append("It also says: \(sentence(extra))")
        }
        let missing = reading.missingImportantFields
        if !missing.isEmpty {
            parts.append("I couldn't read the \(missing.joined(separator: " or ")). "
                + "Try turning it slightly or bringing it closer.")
        }
        if reading.hasMoreDetails {
            parts.append("Tap More Details for the rest.")
        }
        if reading.isLikelyPrescription {
            parts.append("If anything sounds wrong, confirm with your pharmacist.")
        }
        return spokenForm(parts.joined(separator: " "))
    }

    static func details(_ reading: LabelReading) -> String {
        var parts: [String] = []
        if let rx = reading.rxNumber { parts.append("Prescription number \(rx).") }
        if let quantity = reading.quantity { parts.append("Quantity \(quantity).") }
        if let refills = reading.refills { parts.append("\(refills).") }
        if let pharmacy = reading.pharmacy { parts.append("Pharmacy: \(sentence(pharmacy))") }
        if let prescriber = reading.prescriber { parts.append("Prescriber: \(prescriber).") }
        if let filled = reading.dateFilled { parts.append("Filled \(filled).") }
        return parts.isEmpty ? "There are no more details I could read." : spokenForm(parts.joined(separator: " "))
    }

    static func everything(_ reading: LabelReading) -> String {
        guard reading.hasAnyText else { return "I couldn't read any text." }
        return spokenForm(reading.allLines.map(sentence).joined(separator: " "))
    }

    /// Expands abbreviations that speech synthesis reads poorly ("500 MG" -> "500 milligrams").
    static func spokenForm(_ text: String) -> String {
        let replacements: [(String, String)] = [
            (#"(?i)(\d)\s?mcg\b"#, "$1 micrograms"),
            (#"(?i)(\d)\s?mg\b"#, "$1 milligrams"),
            (#"(?i)(\d)\s?ml\b"#, "$1 milliliters"),
            (#"(?i)\btabs\b"#, "tablets"),
            (#"(?i)\btab\b"#, "tablet"),
            (#"(?i)\bcaps\b"#, "capsules"),
            (#"(?i)\bqty\b"#, "quantity")
        ]
        return replacements.reduce(text) { result, pair in
            result.replacingOccurrences(of: pair.0, with: pair.1, options: .regularExpression)
        }
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}
