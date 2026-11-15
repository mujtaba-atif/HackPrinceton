import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Works out what a requested object looks like.
///
/// In order: the object detector (it has a class for it), the catalog of everyday things, then Apple's
/// on-device language model for anything else, which reasons about the thing's appearance and names
/// lookalikes the image classifier knows. The model runs on the phone with no account or key, on devices
/// with Apple Intelligence; elsewhere, labels and colors named in the request itself are the last resort.
enum AppearanceDescriber {
    /// How long Locate waits for the language model before searching with what it already has.
    static let modelTimeout: TimeInterval = 6

    static func describe(_ request: String,
                         classifierLabels: Set<String> = AppearanceScanner.classifierLabels) async -> TargetAppearance? {
        let known = AppearanceCatalog.appearance(for: request, classifierLabels: classifierLabels)
        if let known, known.source != .words { return known }

        let said = AppearanceWords(parsing: request)
        let name = said.remainder.isEmpty ? VoiceCommandParser.normalize(request) : said.remainder
        if let generated = await describeWithLanguageModel(name, classifierLabels: classifierLabels) {
            var merged = generated.merging(said)
            // Labels named in the request itself are the most direct evidence there is.
            for label in known?.classifierLabels ?? [] where !merged.classifierLabels.contains(label) {
                merged.classifierLabels.insert(label, at: 0)
            }
            return merged
        }
        return known
    }

    /// Whether the on-device language model can be asked, for wording ("let me think about what that looks like").
    static var languageModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    private static func describeWithLanguageModel(_ name: String, classifierLabels: Set<String>) async -> TargetAppearance? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            // Not a task group: a group waits for every child before it returns, and the model's
            // `respond` doesn't stop when cancelled, so a group "timeout" still sat out the whole
            // generation. Whichever finishes first answers; a late answer is thrown away.
            return await withCheckedContinuation { continuation in
                let once = ResumeOnce(continuation)
                let model = Task { once.resume(await GeneratedLook.describe(name, classifierLabels: classifierLabels)) }
                Task {
                    try? await Task.sleep(for: .seconds(modelTimeout))
                    if once.resume(nil) {
                        print("Appearance search: language model took over \(Int(modelTimeout)) s describing \(name)")
                        model.cancel()
                    }
                }
            }
        }
        #endif
        return nil
    }

    /// Resumes a continuation the first time only, from whichever task gets there first.
    private final class ResumeOnce: @unchecked Sendable {
        private var continuation: CheckedContinuation<TargetAppearance?, Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<TargetAppearance?, Never>) {
            self.continuation = continuation
        }

        /// Returns true when this call was the one that resumed it.
        @discardableResult
        func resume(_ value: TargetAppearance?) -> Bool {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
            return continuation != nil
        }
    }

    /// Turns the language model's free words into an appearance, keeping only values the search understands.
    static func appearance(name: String, lookalikes: [String], colors: [String], size: String, shape: String,
                           texture: String, container: String, classifierLabels: Set<String>) -> TargetAppearance {
        var labels: [String] = []
        for phrase in [name] + lookalikes {
            for label in AppearanceCatalog.matchingLabels(for: phrase, in: classifierLabels) where !labels.contains(label) {
                labels.append(label)
            }
        }
        let normalizedContainer = container.lowercased().trimmingCharacters(in: .whitespaces)
        return TargetAppearance(
            name: name, source: .languageModel,
            detectorClasses: AppearanceCatalog.detectorClasses.contains(normalizedContainer) ? [normalizedContainer] : [],
            classifierLabels: Array(labels.prefix(4)),
            colors: colors.compactMap { AppearanceColor(rawValue: $0.lowercased().trimmingCharacters(in: .whitespaces)) },
            textures: AppearanceTexture(rawValue: texture.lowercased()).map { [$0] } ?? [],
            shapes: AppearanceShape(rawValue: shape.lowercased()).map { [$0] } ?? [],
            size: AppearanceSize(rawValue: size.lowercased())
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedLook {
    @Guide(description: "Two to five short, common, concrete names of everyday things it looks like or could be mistaken for in a photo, most similar first, as singular nouns.")
    var lookalikes: [String]

    @Guide(description: "Its most likely colors, one to three, each exactly one of: white, black, gray, red, orange, yellow, green, blue, purple, pink, brown.")
    var colors: [String]

    @Guide(description: "How big it looks in a phone photo taken at arm's length.", .anyOf(["tiny", "small", "medium", "large"]))
    var size: String

    @Guide(description: "Its overall outline.", .anyOf(["round", "elongated", "rectangular", "irregular"]))
    var shape: String

    @Guide(description: "Its most visible surface texture.", .anyOf(["shiny", "matte", "patterned", "smooth", "translucent"]))
    var texture: String

    @Guide(description: "The one category from the list given that it is most likely to be, or to be kept inside, or none.")
    var container: String

    static func describe(_ name: String, classifierLabels: Set<String>) async -> TargetAppearance? {
        let session = LanguageModelSession(instructions: """
            You help a blind person find objects with their phone's camera. Describe only how an object \
            usually looks, as plainly and typically as possible.
            """)
        let prompt = """
            Object: \(name)
            Categories for "container": \(AppearanceCatalog.detectorClasses.joined(separator: ", ")), none
            """
        do {
            let look = try await session.respond(to: prompt, generating: GeneratedLook.self).content
            return AppearanceDescriber.appearance(name: name, lookalikes: look.lookalikes, colors: look.colors,
                                                  size: look.size, shape: look.shape, texture: look.texture,
                                                  container: look.container, classifierLabels: classifierLabels)
        } catch {
            print("Appearance search: language model couldn't describe \(name): \(error)")
            return nil
        }
    }
}
#endif
