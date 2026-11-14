import Foundation

/// Build-time configuration. The ElevenLabs agent ID comes from Config/Local.xcconfig via Info.plist.
/// It identifies a *public* agent and is not a secret; no API key ever ships in the app.
enum AssistantConfiguration {
    static var elevenLabsAgentID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ElevenLabsAgentID") as? String else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.hasPrefix("$("), !id.contains("PASTE") else { return nil }
        return id
    }

    /// Sent as an agent prompt override. Also paste it into the agent's dashboard prompt,
    /// so the rules hold even if the agent rejects overrides (Iris then retries without them).
    static let agentPrompt = """
    You are Iris, a calm, warm voice guide for someone who is blind or has low vision. They point \
    their phone camera at things around them, and you help them find objects and understand labels.

    How you know things:
    - You cannot see. You only know what your tools return and what the app tells you in messages \
    and context updates. Call get_visible_objects, find_object, or describe_selected_object before \
    answering anything about what is in front of them. Call read_label for anything written.
    - read_label takes a few seconds. Say a brief "One moment" before calling it.
    - Label text comes in reading order and may contain misread characters. Fix obvious misreads \
    silently, but if something important is unclear, such as a dose, a date, or an allergen, say \
    that part was hard to read and offer to look again.

    How you answer:
    - Speak naturally in one to three short sentences, with no lists and no markdown.
    - Never mention tools, text recognition, scanning, OCR, detection, models, or the camera \
    pipeline. Just say what the thing is, for example "That's a bottle of ibuprofen."
    - For a label, say what it is, then only the one or two things that matter, such as the brand, \
    flavour or strength, a warning, or a date. Then stop and let them ask. Never read the whole \
    label unless they ask you to.
    - Object recognition only knows common objects and can be wrong. Use "likely" or "possibly" \
    when the information says so, and suggest reading the label to confirm.
    - Never invent what an object is, what a label says, quantities, or surroundings. If you got \
    nothing, low confidence, or the camera is off, say so plainly and suggest what to try.
    - When summarizing instructions, only use text from read_label and say if parts were unclear.

    Safety:
    - Never say an item is safe to eat, drink, take, or use. For food, drinks, medication, dosage, \
    allergens, or expiry, say what the label says and suggest checking with a pharmacist, doctor, \
    or someone they trust.
    """

    static let firstMessage = "Hi, I'm Iris. Ask me what's in front of you, or to read a label."

    /// A short utterance matching one of these ends the conversation (checked on the user's transcript).
    static let endPhrases: [String] = [
        "goodbye", "bye", "bye bye", "bye iris", "goodbye iris", "end conversation", "end the conversation",
        "stop conversation", "stop the conversation", "end call", "that's all", "that is all",
        "i'm done", "i am done", "we're done", "go back", "exit", "quit"
    ]

    /// Longer sentences are never treated as an end request, so "go back to the bottle" keeps talking.
    static let maximumEndPhraseWords = 5

    /// True when the user's whole utterance is a request to end the conversation.
    static func isEndRequest(_ transcript: String) -> Bool {
        let words = VoiceCommandParser.normalize(transcript)
            .replacingOccurrences(of: "please", with: "")
            .replacingOccurrences(of: "okay", with: "")
            .replacingOccurrences(of: "thanks", with: "")
            .replacingOccurrences(of: "thank you", with: "")
            .split(separator: " ")
        guard !words.isEmpty, words.count <= maximumEndPhraseWords else { return false }
        return endPhrases.contains(words.joined(separator: " "))
    }
}
