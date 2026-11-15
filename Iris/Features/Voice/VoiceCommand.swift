import Foundation

/// A structured interpretation of something the user said.
enum VoiceCommand: Equatable, Sendable {
    /// "What am I looking at?" / "What is this?"
    case identify
    /// "Read this label" / "What does this say?"
    case readText
    /// "Find my water bottle" → `.find("water bottle")`
    case find(String)
    /// "What objects are nearby?"
    case listObjects
    /// "Stop speaking" / "Be quiet"
    case stopSpeaking
    /// Anything else: an open question for the assistant.
    case ask(String)
}

/// Pure, deterministic phrase matching so commands work offline and are fully testable.
enum VoiceCommandParser {
    static func parse(_ transcript: String) -> VoiceCommand? {
        let text = normalize(transcript)
        guard !text.isEmpty else { return nil }

        if matches(text, any: ["stop speaking", "stop talking", "be quiet", "quiet", "shut up", "stop", "silence", "cancel"]) {
            return .stopSpeaking
        }
        if contains(text, any: ["read", "what does this say", "what does it say", "what does that say",
                                "what's written", "what is written", "label say", "text say"]) {
            return .readText
        }
        if contains(text, any: ["objects nearby", "objects around", "what's around", "what is around",
                                "what do you see", "what can you see", "which objects", "what objects",
                                "list objects", "anything nearby", "what's nearby", "what is nearby", "around me"]) {
            return .listObjects
        }
        if let target = findTarget(in: text) {
            return target.isEmpty ? .listObjects : .find(target)
        }
        if contains(text, any: ["what am i looking at", "what is this", "what's this", "what is that", "what's that",
                                "identify", "what am i holding", "what is in front of me", "what's in front of me"]) {
            return .identify
        }
        return .ask(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let findPrefixes = [
        "can you help me find", "could you help me find", "help me find", "can you find", "could you find",
        "i'm looking for", "i am looking for", "i'm trying to find", "i am trying to find", "i need to find",
        "i want to find", "where is", "where's", "where are", "look for", "search for", "locate", "find"
    ]
    private static let fillerWords: Set<String> = ["a", "an", "the", "my", "some", "this", "that", "me", "please", "for"]

    /// Extracts the object name from a find request: "can you find my water bottle please" → "water bottle".
    static func findTarget(in normalized: String) -> String? {
        let polite = ["hey iris ", "iris ", "please ", "okay ", "ok "]
        var text = normalized
        for prefix in polite where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        guard let prefix = findPrefixes.first(where: { text == $0 || text.hasPrefix($0 + " ") }) else { return nil }
        var words = text.dropFirst(prefix.count).split(separator: " ").map(String.init)
        while let first = words.first, fillerWords.contains(first) { words.removeFirst() }
        while let last = words.last, fillerWords.contains(last) || last == "is" || last == "at" { words.removeLast() }
        return words.joined(separator: " ")
    }

    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "' "))
        let cleaned = String(String.UnicodeScalarView(lowered.unicodeScalars.filter { allowed.contains($0) }))
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    private static func contains(_ text: String, any phrases: [String]) -> Bool {
        let padded = " \(text) "
        return phrases.contains { padded.contains(" \($0) ") }
    }

    private static func matches(_ text: String, any phrases: [String]) -> Bool {
        let trimmed = text.replacingOccurrences(of: "please", with: "").trimmingCharacters(in: .whitespaces)
        // Single words like "stop" must be the whole utterance; phrases may be followed by more words.
        return phrases.contains { trimmed == $0 || ($0.contains(" ") && trimmed.hasPrefix($0 + " ")) }
    }
}
