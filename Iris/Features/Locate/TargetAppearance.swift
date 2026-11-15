import Foundation

// What a requested object looks like, for finding things the object detector has no class for.
//
// The detector knows 80 everyday categories (bottle, cup, phone…). Pills, keys, a wallet or a pill bottle
// among other bottles are not among them, and matching the spoken word against those 80 names alone can
// never find them. So a request is first turned into a description of the thing's appearance: which of
// Apple's on-device image-classifier labels fit it, its likely colors, texture, shape and size, and which
// detector classes it may show up inside. `AppearanceSearch` then looks for regions of the camera image that
// match that description.

enum AppearanceColor: String, CaseIterable, Sendable {
    case white, black, gray, red, orange, yellow, green, blue, purple, pink, brown
}

enum AppearanceTexture: String, CaseIterable, Sendable {
    /// Glossy plastic, metal, glass: small specular highlights.
    case shiny
    /// Flat, even, few highlights (paper, fabric, most pills).
    case matte
    /// Lots of fine detail: print, weave, leather grain, a pile of small things.
    case patterned
    /// Plain and even, with little detail.
    case smooth
    /// Tinted see-through plastic or glass; measured as some gloss over an even surface.
    case translucent
}

enum AppearanceShape: String, CaseIterable, Sendable {
    case round, elongated, rectangular, irregular
}

/// How much of the camera image the thing covers at roughly arm's length.
enum AppearanceSize: String, CaseIterable, Sendable {
    case tiny, small, medium, large
}

struct TargetAppearance: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// The object detector has a class for it; no appearance search is needed.
        case detector(String)
        /// A hand-written entry for everyday items people often need to find.
        case catalog
        /// Described by the on-device language model.
        case languageModel
        /// Only the words of the request: classifier labels named in it and any colors or sizes said.
        case words
    }

    var name: String
    var source: Source
    /// Detector classes it may be detected as or inside ("pill bottle" → "bottle"), used as search regions.
    var detectorClasses: [String] = []
    /// Identifiers of Apple's `VNClassifyImageRequest` that fit it.
    var classifierLabels: [String] = []
    var colors: [AppearanceColor] = []
    var textures: [AppearanceTexture] = []
    var shapes: [AppearanceShape] = []
    var size: AppearanceSize?

    /// The object detector finds it by itself.
    var usesDetector: Bool {
        if case .detector = source { return true }
        return false
    }

    /// Enough is known about it to search: a classifier label, or at least two appearance cues.
    var isSearchable: Bool {
        if !classifierLabels.isEmpty || !detectorClasses.isEmpty { return true }
        let cues = [!colors.isEmpty, !textures.isEmpty, !shapes.isEmpty, size != nil].filter { $0 }.count
        return cues >= 2
    }

    /// "small, round and white or yellow", spoken to say what Iris is looking for.
    var spokenLook: String {
        var parts: [String] = []
        if let size, size != .medium { parts.append(size.rawValue) }
        if let shape = shapes.first, shape != .irregular {
            parts.append(shapes.count > 1 && shapes[1] != .irregular ? "\(shape.rawValue) or \(shapes[1].rawValue)" : shape.rawValue)
        }
        if let texture = textures.first, texture != .smooth { parts.append(texture.rawValue) }
        var look = parts.joined(separator: ", ")
        if !colors.isEmpty {
            let named = colors.prefix(3).map(\.rawValue)
            let colorWords = named.count == 1 ? named[0]
                : named.dropLast().joined(separator: ", ") + " or " + named.last!
            look += look.isEmpty ? colorWords : " and \(colorWords)"
        }
        return look
    }

    /// Adds what the user said ("the small orange one") on top of what is known about the thing.
    /// Their words win: a color they name replaces the guessed ones.
    func merging(_ said: AppearanceWords) -> TargetAppearance {
        var merged = self
        if !said.colors.isEmpty { merged.colors = said.colors }
        if !said.textures.isEmpty { merged.textures = said.textures }
        if !said.shapes.isEmpty { merged.shapes = said.shapes }
        if let size = said.size { merged.size = size }
        return merged
    }
}

/// Appearance words in a request: "find the small orange bottle" → small, orange.
struct AppearanceWords: Equatable, Sendable {
    var colors: [AppearanceColor] = []
    var textures: [AppearanceTexture] = []
    var shapes: [AppearanceShape] = []
    var size: AppearanceSize?
    /// The request with those words taken out ("bottle").
    var remainder: String = ""

    private static let colorWords: [String: AppearanceColor] = [
        "white": .white, "black": .black, "gray": .gray, "grey": .gray, "silver": .gray, "red": .red,
        "orange": .orange, "yellow": .yellow, "gold": .yellow, "golden": .yellow, "green": .green,
        "blue": .blue, "navy": .blue, "purple": .purple, "violet": .purple, "pink": .pink, "brown": .brown,
        "tan": .brown, "beige": .brown
    ]
    private static let textureWords: [String: AppearanceTexture] = [
        "shiny": .shiny, "glossy": .shiny, "metal": .shiny, "metallic": .shiny, "silver": .shiny,
        "gold": .shiny, "golden": .shiny, "matte": .matte, "fuzzy": .patterned, "furry": .patterned,
        "striped": .patterned, "patterned": .patterned, "plaid": .patterned, "leather": .patterned,
        "plain": .smooth, "smooth": .smooth, "clear": .translucent, "transparent": .translucent,
        "translucent": .translucent, "glass": .translucent
    ]
    private static let shapeWords: [String: AppearanceShape] = [
        "round": .round, "circular": .round, "oval": .round, "long": .elongated, "thin": .elongated,
        "skinny": .elongated, "tall": .elongated, "square": .rectangular, "rectangular": .rectangular,
        "flat": .rectangular
    ]
    private static let sizeWords: [String: AppearanceSize] = [
        "tiny": .tiny, "little": .small, "small": .small, "mini": .small, "big": .large, "large": .large,
        "huge": .large
    ]

    init(colors: [AppearanceColor] = [], textures: [AppearanceTexture] = [], shapes: [AppearanceShape] = [],
         size: AppearanceSize? = nil, remainder: String = "") {
        self.colors = colors
        self.textures = textures
        self.shapes = shapes
        self.size = size
        self.remainder = remainder
    }

    /// The last word is always the thing's name, never a description of it: in "wine glass" or "orange"
    /// the glass and the orange are what is wanted, where in "glass bottle" or "orange pills" they
    /// describe it. English puts the noun last, so that is the rule used.
    init(parsing request: String) {
        var rest: [String] = []
        let words = VoiceCommandParser.normalize(request).split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            if index == words.count - 1 {
                rest.append(word)
                continue
            }
            var used = false
            if let color = Self.colorWords[word] {
                if !colors.contains(color) { colors.append(color) }
                used = true
            }
            if let texture = Self.textureWords[word] {
                if !textures.contains(texture) { textures.append(texture) }
                used = true
            }
            if let shape = Self.shapeWords[word] {
                if !shapes.contains(shape) { shapes.append(shape) }
                used = true
            }
            if let size = Self.sizeWords[word] {
                self.size = size
                used = true
            }
            if !used { rest.append(word) }
        }
        remainder = rest.joined(separator: " ")
    }
}

/// Turns a spoken request into a `TargetAppearance`, without any network.
enum AppearanceCatalog {
    /// The object detector's classes (`YOLOv3TinyFP16`, see `ObjectDetection/Resources/MODEL.md`).
    static let detectorClasses = [
        "person", "bicycle", "car", "motorbike", "aeroplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse",
        "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie",
        "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
        "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon",
        "bowl", "banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut",
        "cake", "chair", "sofa", "pottedplant", "bed", "diningtable", "toilet", "tvmonitor", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
        "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]

    struct Entry {
        let names: [String]
        let detectorClasses: [String]
        let classifierLabels: [String]
        let colors: [AppearanceColor]
        let textures: [AppearanceTexture]
        let shapes: [AppearanceShape]
        let size: AppearanceSize
    }

    /// Everyday things people often need to find that the detector has no class for, or has only a vaguer
    /// one for (a pill bottle is a bottle, but so is every other bottle). More specific names come first.
    static let entries: [Entry] = [
        Entry(names: ["pill bottle", "medicine bottle", "prescription bottle", "prescription", "pill container",
                      "medication bottle", "vitamin bottle", "vitamins", "supplements"],
              detectorClasses: ["bottle"], classifierLabels: ["medicine", "bottle"],
              colors: [.orange, .white, .brown], textures: [.translucent, .shiny], shapes: [.elongated, .round],
              size: .small),
        Entry(names: ["pill", "pills", "tablet", "tablets", "capsule", "capsules", "medication", "medicine",
                      "meds", "painkiller", "painkillers", "aspirin", "tylenol", "advil", "ibuprofen"],
              detectorClasses: [], classifierLabels: ["medicine"],
              colors: [.white, .yellow, .orange, .pink, .red, .blue], textures: [.smooth, .matte],
              shapes: [.round, .elongated], size: .tiny),
        Entry(names: ["keys", "key", "keychain", "car keys", "house keys", "key ring"],
              detectorClasses: [], classifierLabels: [],
              colors: [.gray, .yellow], textures: [.shiny], shapes: [.irregular, .elongated], size: .small),
        Entry(names: ["wallet", "billfold", "purse wallet", "card holder"],
              detectorClasses: [], classifierLabels: ["wallet"],
              colors: [.black, .brown], textures: [.matte, .patterned], shapes: [.rectangular], size: .small),
        Entry(names: ["sunglasses", "shades"],
              detectorClasses: [], classifierLabels: ["sunglasses", "eyeglasses"],
              colors: [.black, .brown, .gray], textures: [.shiny], shapes: [.elongated], size: .small),
        Entry(names: ["glasses", "eyeglasses", "reading glasses", "spectacles"],
              detectorClasses: [], classifierLabels: ["eyeglasses", "sunglasses"],
              colors: [.black, .brown, .gray], textures: [.shiny], shapes: [.elongated], size: .small),
        Entry(names: ["coin", "coins", "change", "quarter", "quarters", "penny", "pennies", "dime", "nickel"],
              detectorClasses: [], classifierLabels: ["coin", "money"],
              colors: [.gray, .yellow, .brown], textures: [.shiny], shapes: [.round], size: .tiny),
        Entry(names: ["credit card", "debit card", "card", "id card", "gift card", "bank card"],
              detectorClasses: [], classifierLabels: ["credit_card", "gift_card"],
              colors: [], textures: [.shiny, .smooth], shapes: [.rectangular], size: .small),
        Entry(names: ["cash", "money", "bills", "dollar", "dollars"],
              detectorClasses: [], classifierLabels: ["money", "currency"],
              colors: [.green, .gray], textures: [.patterned], shapes: [.rectangular], size: .small),
        Entry(names: ["can", "soda can", "soda", "pop can", "soup can", "tin can", "beer can", "drink can"],
              detectorClasses: ["bottle", "cup"], classifierLabels: ["soda", "drink", "beer"],
              colors: [], textures: [.shiny], shapes: [.elongated, .round], size: .small),
        Entry(names: ["jar", "spice jar", "spice", "spices", "seasoning", "salt", "pepper shaker"],
              detectorClasses: ["bottle", "cup"], classifierLabels: ["jar", "spice", "condiment"],
              colors: [], textures: [.translucent, .shiny], shapes: [.round, .elongated], size: .small),
        Entry(names: ["watch", "wristwatch", "smartwatch"],
              detectorClasses: [], classifierLabels: ["watch"],
              colors: [.black, .gray], textures: [.shiny], shapes: [.round, .rectangular], size: .tiny),
        Entry(names: ["ring", "necklace", "bracelet", "earrings", "earring", "jewelry", "jewellery"],
              detectorClasses: [], classifierLabels: ["jewelry"],
              colors: [.yellow, .gray], textures: [.shiny], shapes: [.round, .irregular], size: .tiny),
        Entry(names: ["earbuds", "airpods", "earphones", "headphones", "headset"],
              detectorClasses: [], classifierLabels: ["headphones"],
              colors: [.white, .black], textures: [.shiny, .smooth], shapes: [.round, .rectangular], size: .small),
        Entry(names: ["charger", "charging cable", "cable", "cord", "phone charger", "usb cable"],
              detectorClasses: [], classifierLabels: ["cord", "consumer_electronics"],
              colors: [.white, .black], textures: [.smooth], shapes: [.elongated, .irregular], size: .small),
        Entry(names: ["pen", "pencil", "marker"],
              detectorClasses: [], classifierLabels: ["pen"],
              colors: [], textures: [.smooth, .shiny], shapes: [.elongated], size: .small),
        Entry(names: ["lighter"],
              detectorClasses: [], classifierLabels: ["lighter"],
              colors: [], textures: [.shiny], shapes: [.elongated, .rectangular], size: .tiny),
        Entry(names: ["mail", "letter", "letters", "envelope", "envelopes"],
              detectorClasses: [], classifierLabels: ["envelope", "document"],
              colors: [.white, .brown], textures: [.matte, .smooth], shapes: [.rectangular], size: .medium),
        Entry(names: ["receipt", "receipts"],
              detectorClasses: [], classifierLabels: ["receipt", "document"],
              colors: [.white], textures: [.matte, .patterned], shapes: [.elongated, .rectangular], size: .small),
        Entry(names: ["hat", "cap", "baseball cap", "beanie"],
              detectorClasses: [], classifierLabels: ["hat", "baseball_hat"],
              colors: [], textures: [.matte, .patterned], shapes: [.round, .irregular], size: .medium),
        Entry(names: ["glove", "gloves", "mittens"],
              detectorClasses: [], classifierLabels: ["glove", "glove_other"],
              colors: [], textures: [.matte, .patterned], shapes: [.irregular], size: .small),
        Entry(names: ["mask", "face mask"],
              detectorClasses: [], classifierLabels: ["mask"],
              colors: [.white, .blue, .black], textures: [.matte], shapes: [.rectangular], size: .small),
        Entry(names: ["thermometer"],
              detectorClasses: [], classifierLabels: ["thermometer"],
              colors: [.white], textures: [.smooth, .shiny], shapes: [.elongated], size: .tiny),
        Entry(names: ["syringe", "insulin pen", "epipen", "epi pen"],
              detectorClasses: [], classifierLabels: ["syringe", "medicine"],
              colors: [], textures: [.smooth, .shiny], shapes: [.elongated], size: .small),
        Entry(names: ["flashlight", "torch"],
              detectorClasses: [], classifierLabels: ["flashlight"],
              colors: [.black, .gray], textures: [.shiny], shapes: [.elongated], size: .small),
        Entry(names: ["sock", "socks", "shoe", "shoes", "sneaker", "sneakers", "sandal", "sandals", "slippers"],
              detectorClasses: [], classifierLabels: ["sock", "shoes", "sneaker", "sandal"],
              colors: [], textures: [.matte, .patterned], shapes: [.elongated, .irregular], size: .medium),
        Entry(names: ["snack", "chips", "candy", "chocolate", "cookie", "cookies", "granola bar"],
              detectorClasses: [], classifierLabels: ["candy", "chocolate", "cookie", "candy_other"],
              colors: [], textures: [.shiny, .patterned], shapes: [.rectangular, .irregular], size: .small),
        Entry(names: ["cereal", "cereal box"],
              detectorClasses: [], classifierLabels: ["cereal", "cardboard_box"],
              colors: [], textures: [.patterned], shapes: [.rectangular], size: .medium)
    ]

    /// The appearance for a request, from the detector or the catalog; `nil` when neither knows it.
    /// - Parameter classifierLabels: The classifier's identifiers, for naming labels the request mentions.
    static func appearance(for request: String, classifierLabels: Set<String> = []) -> TargetAppearance? {
        let said = AppearanceWords(parsing: request)
        let name = said.remainder.isEmpty ? VoiceCommandParser.normalize(request) : said.remainder
        guard !name.isEmpty else { return nil }

        // A catalog entry wins over a vaguer detector class: "pill bottle" must not mean any bottle.
        if let entry = entry(for: name) {
            return TargetAppearance(name: name, source: .catalog, detectorClasses: entry.detectorClasses,
                                    classifierLabels: entry.classifierLabels, colors: entry.colors,
                                    textures: entry.textures, shapes: entry.shapes, size: entry.size)
                .merging(said)
        }
        // A plain detector class, unless the user also described it (the red cup among cups).
        if let detected = detectorClass(for: name) {
            if said.colors.isEmpty, said.textures.isEmpty, said.shapes.isEmpty, said.size == nil {
                return TargetAppearance(name: name, source: .detector(detected))
            }
            return TargetAppearance(name: name, source: .catalog, detectorClasses: [detected]).merging(said)
        }
        let labels = matchingLabels(for: name, in: classifierLabels)
        let fromWords = TargetAppearance(name: name, source: .words, classifierLabels: labels).merging(said)
        return fromWords.isSearchable ? fromWords : nil
    }

    static func entry(for name: String) -> Entry? {
        let normalized = VoiceCommandParser.normalize(name)
        let words = Set(normalized.split(separator: " ").map(String.init))
        // Whole-phrase matches first, so "pill bottle" isn't taken by "pills" further down.
        if let exact = entries.first(where: { $0.names.contains(normalized) }) { return exact }
        return entries.first { entry in
            entry.names.contains { name in
                name.contains(" ") ? normalized.contains(name) : words.contains(name)
            }
        }
    }

    /// The detector class a name means, by the same rules Locate uses to pick a detection
    /// ("water bottle" → bottle, "phone" → cell phone, "mug" → cup), but on whole words only:
    /// that matching is by substring, which would make a scarf a car and a catalog a cat.
    static func detectorClass(for name: String) -> String? {
        let candidates = detectorClasses.map {
            VisibleObject(DetectedObject(id: UUID(), name: $0, confidence: 1, boundingBox: .zero))
        }
        let normalized = VoiceCommandParser.normalize(name)
        var words = normalized.split(separator: " ").map(String.init)
        words += words.compactMap { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : nil }
        // What the words mean, by Locate's synonyms: "television" → tv, "plant" → potted plant.
        let meant = ([normalized] + words).compactMap { AssistantFacts.synonyms[$0] }

        // The run-together classes first: the generic matching below is by substring, and neither
        // "tv monitor" nor "dining table" is a substring of the class it names.
        for (compound, spaced) in compoundClassNames {
            let classWords = Set(spaced.split(separator: " ").map(String.init))
            if words.contains(where: classWords.contains) { return compound }
            if meant.contains(where: { Set($0.split(separator: " ").map(String.init)).isSubset(of: classWords) }) {
                return compound
            }
        }

        guard let matched = AssistantFacts.match(name, in: candidates)?.name else { return nil }
        let classWords = matched.split(separator: " ").map(String.init)
        if classWords.contains(where: words.contains) { return matched }
        return meant.contains(matched) ? matched : nil
    }

    /// Class names the model writes run together, with the words they are made of, so that "tv",
    /// "table" and "plant" still count as whole-word matches.
    private static let compoundClassNames = [
        "tvmonitor": "tv monitor", "diningtable": "dining table", "pottedplant": "potted plant"
    ]

    /// Classifier identifiers named in the request: "umbrella" → umbrella, "board game" → board_game.
    static func matchingLabels(for name: String, in labels: Set<String>) -> [String] {
        guard !labels.isEmpty else { return [] }
        let normalized = VoiceCommandParser.normalize(name)
        var words = normalized.split(separator: " ").map(String.init)
        words += words.compactMap { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : nil }
        var found: [String] = []
        let phrase = normalized.replacingOccurrences(of: " ", with: "_")
        if labels.contains(phrase) { found.append(phrase) }
        for word in words where labels.contains(word) && !found.contains(word) {
            found.append(word)
        }
        return found
    }
}
