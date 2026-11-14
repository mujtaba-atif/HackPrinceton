import Foundation

/// Deterministic, grounded descriptions built only from `AssistantContext` (real detections), plus
/// matching a spoken object name to a detection for Locate and Iris's safety wording.
enum AssistantFacts {
    static let safetyNote = "I can't confirm whether anything is safe to eat, drink, or take. Please check the label with someone you trust, a pharmacist, or a doctor."

    private static let safetyKeywords = [
        "safe", "eat", "eating", "drink", "drinking", "swallow", "consume", "edible", "take", "taking",
        "medicine", "medication", "pill", "pills", "tablet", "dose", "dosage", "allergy", "allergic", "allergen",
        "expired", "expiration", "expire", "poison", "poisonous", "toxic", "food", "ingredients", "contains"
    ]

    /// True when a question or text touches on consumption, medication, or allergens.
    static func needsSafetyNote(_ text: String) -> Bool {
        let words = Set(VoiceCommandParser.normalize(text).split(separator: " ").map(String.init))
        return safetyKeywords.contains { words.contains($0) }
    }

    static func withSafetyNote(_ answer: String, for question: String) -> String {
        guard needsSafetyNote(question) || needsSafetyNote(answer), !answer.contains(safetyNote) else { return answer }
        return answer + " " + safetyNote
    }

    // MARK: Objects

    static func visibleObjects(_ context: AssistantContext) -> String {
        guard context.isCameraRunning else { return "The camera isn't running, so I can't see anything right now." }
        guard !context.objects.isEmpty else {
            return "I don't detect any objects I recognize right now. Try moving the camera slowly. I can only recognize common objects."
        }
        let list = context.objects.prefix(6).map { "\($0.confidenceWord) \(a($0.name)) \($0.position)" }
        let more = context.objects.count > 6 ? " and \(context.objects.count - 6) more" : ""
        return "I can see " + joinList(Array(list)) + more + "."
    }

    static func identify(_ context: AssistantContext) -> String {
        guard context.isCameraRunning else { return "The camera isn't running, so I can't see anything right now." }
        if let selected = context.selected {
            return describeSelected(selected)
        }
        let ahead = context.objects.filter { $0.position == "ahead" }
        guard let best = ahead.first ?? context.objects.first else {
            return "I can't identify anything in front of you right now. Try pointing the camera at the object from about half a meter away. I can also read its label if you ask."
        }
        var answer = "That's \(best.confidenceWord) \(a(best.name)) \(best.position)"
        answer += best.confidence < 0.5 ? ", but I'm not confident." : "."
        answer += " Identification can be wrong, so ask me to read the label to confirm."
        return answer
    }

    static func describeSelected(_ context: AssistantContext) -> String {
        guard let selected = context.selected else { return "No object is selected." }
        return describeSelected(selected)
    }

    private static func describeSelected(_ selected: SelectedObjectTarget) -> String {
        let object = VisibleObject(selected.object)
        switch selected.state {
        case .tracking:
            return "Your selected object is \(object.confidenceWord) \(a(object.name)), \(object.position)."
        case .lost:
            return "I've lost sight of the selected \(object.name). Move the camera slowly to find it again."
        }
    }

    // MARK: Find

    private static let synonyms: [String: String] = [
        "phone": "cell phone", "mobile": "cell phone", "iphone": "cell phone", "cellphone": "cell phone",
        "mug": "cup", "sofa": "couch", "television": "tv", "computer": "laptop",
        "notebook": "laptop", "remote control": "remote", "plant": "potted plant", "table": "dining table",
        "bag": "handbag", "purse": "handbag"
    ]

    /// Best detected object matching a spoken name ("water bottle" → "bottle", "my phone" → "cell phone").
    static func match(_ spokenName: String, in objects: [VisibleObject]) -> VisibleObject? {
        let target = singular(VoiceCommandParser.normalize(spokenName))
        guard !target.isEmpty else { return nil }
        let candidates = [target, synonyms[target]].compactMap { $0 }
            + target.split(separator: " ").compactMap { synonyms[String($0)] }
        func score(_ object: VisibleObject) -> Int {
            let name = object.name.lowercased()
            if candidates.contains(name) { return 3 }
            if candidates.contains(where: { $0.contains(name) }) { return 2 } // "water bottle" ⊇ "bottle"
            if name.contains(target) { return 1 }
            return 0
        }
        return objects
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .max { ($0.1, $0.0.confidence) < ($1.1, $1.0.confidence) }?.0
    }

    static func find(_ spokenName: String, in context: AssistantContext) -> (answer: String, match: VisibleObject?) {
        guard context.isCameraRunning else {
            return ("The camera isn't running, so I can't look for the \(spokenName) yet.", nil)
        }
        guard let match = match(spokenName, in: context.objects) else {
            return ("I don't see \(a(spokenName)) right now. Slowly sweep the camera around. I can only recognize common objects, so it may not be detected.", nil)
        }
        let note = match.name.lowercased() == spokenName.lowercased() ? "" : " I'm matching it as \(a(match.name))."
        return ("I found \(match.confidenceWord) \(a(match.name)) \(match.position). I've selected it.\(note)", match)
    }

    // MARK: Helpers

    /// "a bottle", "an apple".
    static func a(_ noun: String) -> String {
        guard let first = noun.lowercased().first else { return noun }
        return ("aeiou".contains(first) ? "an " : "a ") + noun
    }

    private static func singular(_ text: String) -> String {
        guard text.count > 3, text.hasSuffix("s"), !text.hasSuffix("ss"), !text.hasSuffix("glasses") else { return text }
        return String(text.dropLast())
    }

    private static func joinList(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
