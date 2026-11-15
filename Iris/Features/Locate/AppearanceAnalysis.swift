import CoreGraphics
import Foundation

/// Color and texture measured over part of a camera image.
struct AppearanceSample: Equatable, Sendable {
    /// Fraction of the sampled pixels falling in each named color.
    var colorFractions: [AppearanceColor: Double] = [:]
    /// Fraction of pixels that are specular highlights (near-white and unsaturated): gloss, metal, glass.
    var gloss: Double = 0
    /// Mean luminance step between neighbouring pixels, 0...1: print, weave, grain, or a pile of small things.
    var detail: Double = 0
}

/// Where a search region came from. Windows (`tile`) say nothing about the object's own size or shape.
enum AppearanceRegionKind: Equatable, Sendable {
    /// A detection of one of the appearance's detector classes.
    case detection
    /// A class-agnostic "something is here" region from Vision's objectness saliency.
    case salient
    /// A fixed window of the frame, so small things that nothing else proposes still get looked at.
    case tile
}

struct ScoredRegion: Equatable, Sendable {
    /// Vision coordinates (normalized, upright, bottom-left origin).
    var box: CGRect
    var kind: AppearanceRegionKind
    /// Best classifier confidence among the appearance's labels, if the classifier ran.
    var classifierConfidence: Double?
    /// Color, texture, shape and size agreement, 0...1, if the appearance has any of those cues.
    var appearanceScore: Double?
    var score: Double
}

/// Measures and scores how well a region of the image matches a `TargetAppearance`. All pure functions.
enum AppearanceAnalyzer {
    struct Weights {
        var color = 0.45
        var texture = 0.25
        var shape = 0.1
        var size = 0.2
        /// Share of the final score from the classifier when both it and appearance are available.
        var classifier = 0.6
        /// Classifier confidence treated as certain; crops rarely score higher than this.
        var classifierCeiling = 0.25
        /// Added for a region the detector found as one of the appearance's detector classes.
        var detectionBonus = 0.1
    }

    // MARK: Pixels

    /// The named color of one pixel, by hue, saturation and brightness.
    static func color(red: UInt8, green: UInt8, blue: UInt8) -> AppearanceColor {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maximum = max(r, g, b), minimum = min(r, g, b)
        let value = maximum
        let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
        if value < 0.2 { return .black }
        if saturation < 0.18 { return value > 0.78 ? .white : .gray }
        var hue: Double
        let delta = maximum - minimum
        if maximum == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        // Dark oranges and reds read as brown; pale reds as pink.
        if (10..<50).contains(hue), value < 0.55 { return .brown }
        switch hue {
        case 345..., ..<12: return saturation < 0.5 && value > 0.7 ? .pink : .red
        case 12..<40: return .orange
        case 40..<70: return .yellow
        case 70..<165: return .green
        case 165..<255: return .blue
        case 255..<290: return .purple
        default: return .pink
        }
    }

    /// Samples an RGBA8 bitmap (row 0 at the top) over the central 60% of a Vision-coordinates region,
    /// where the object is most likely to be rather than its background.
    static func sample(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                       region: CGRect) -> AppearanceSample? {
        let inner = region.insetBy(dx: region.width * 0.2, dy: region.height * 0.2)
        let x0 = max(0, Int(inner.minX * CGFloat(width))), x1 = min(width, Int(ceil(inner.maxX * CGFloat(width))))
        let y0 = max(0, Int((1 - inner.maxY) * CGFloat(height)))
        let y1 = min(height, Int(ceil((1 - inner.minY) * CGFloat(height))))
        guard x1 - x0 >= 2, y1 - y0 >= 2, rgba.count >= bytesPerRow * height else { return nil }

        var counts: [AppearanceColor: Int] = [:]
        var glossy = 0, total = 0
        var detailSum = 0.0, detailCount = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = y * bytesPerRow + x * 4
                let r = rgba[i], g = rgba[i + 1], b = rgba[i + 2]
                counts[color(red: r, green: g, blue: b), default: 0] += 1
                let high = max(r, g, b), low = min(r, g, b)
                if high > 235, Int(high) - Int(low) < 30 { glossy += 1 }
                total += 1
                if x + 1 < x1, y + 1 < y1 {
                    let luma = Self.luma(r, g, b)
                    let right = y * bytesPerRow + (x + 1) * 4, below = (y + 1) * bytesPerRow + x * 4
                    detailSum += abs(luma - Self.luma(rgba[right], rgba[right + 1], rgba[right + 2]))
                        + abs(luma - Self.luma(rgba[below], rgba[below + 1], rgba[below + 2]))
                    detailCount += 2
                }
            }
        }
        guard total > 0 else { return nil }
        return AppearanceSample(colorFractions: counts.mapValues { Double($0) / Double(total) },
                                gloss: Double(glossy) / Double(total),
                                detail: detailCount > 0 ? detailSum / Double(detailCount) : 0)
    }

    private static func luma(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255
    }

    // MARK: Cues

    /// How much of the region is one of the expected colors; a third of it counts as a full match.
    static func colorScore(_ sample: AppearanceSample, expected: [AppearanceColor]) -> Double? {
        guard !expected.isEmpty else { return nil }
        let fraction = expected.reduce(0) { $0 + (sample.colorFractions[$1] ?? 0) }
        return min(1, fraction / 0.33)
    }

    static func textureScore(_ sample: AppearanceSample, expected: [AppearanceTexture]) -> Double? {
        guard !expected.isEmpty else { return nil }
        let shiny = min(1, sample.gloss / 0.03)
        let detailed = min(1, sample.detail / 0.08)
        func score(_ texture: AppearanceTexture) -> Double {
            switch texture {
            case .shiny: shiny
            case .matte: (1 - shiny) * (1 - 0.5 * detailed)
            case .patterned: detailed
            case .smooth: 1 - detailed
            case .translucent: 0.5 * shiny + 0.5 * (1 - detailed)
            }
        }
        return expected.map(score).max()
    }

    /// From the region's aspect ratio in image pixels (`imageAspect` is image width / height).
    static func shapeScore(_ box: CGRect, imageAspect: Double, expected: [AppearanceShape]) -> Double? {
        guard !expected.isEmpty, box.height > 0 else { return nil }
        let stretch = abs(log(Double(box.width / box.height) * imageAspect))
        func score(_ shape: AppearanceShape) -> Double {
            switch shape {
            case .round: max(0, 1 - stretch / log(1.8))
            case .elongated: min(1, max(0, (stretch - log(1.3)) / log(1.6)))
            case .rectangular: max(0.4, 1 - stretch / log(4))
            case .irregular: 0.6
            }
        }
        return expected.map(score).max()
    }

    /// From the fraction of the image the region covers, at roughly arm's length.
    static func sizeScore(_ box: CGRect, expected: AppearanceSize?) -> Double? {
        guard let expected else { return nil }
        let area = Double(box.width * box.height)
        switch expected {
        case .tiny: return area <= 0.02 ? 1 : max(0, 1 - (area - 0.02) / 0.08)
        case .small: return area < 0.004 ? area / 0.004 : area <= 0.1 ? 1 : max(0, 1 - (area - 0.1) / 0.15)
        case .medium: return area < 0.03 ? area / 0.03 : area <= 0.4 ? 1 : max(0, 1 - (area - 0.4) / 0.3)
        case .large: return min(1, area / 0.25)
        }
    }

    /// Color, texture, shape and size combined; shape and size only for regions that are objects, not windows.
    static func appearanceScore(_ sample: AppearanceSample, box: CGRect, kind: AppearanceRegionKind,
                                appearance: TargetAppearance, imageAspect: Double,
                                weights: Weights = Weights()) -> Double? {
        var parts: [(score: Double, weight: Double)] = []
        if let color = colorScore(sample, expected: appearance.colors) { parts.append((color, weights.color)) }
        if let texture = textureScore(sample, expected: appearance.textures) { parts.append((texture, weights.texture)) }
        if kind != .tile {
            if let shape = shapeScore(box, imageAspect: imageAspect, expected: appearance.shapes) {
                parts.append((shape, weights.shape))
            }
            if let size = sizeScore(box, expected: appearance.size) { parts.append((size, weights.size)) }
        }
        let weight = parts.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        let blended = parts.reduce(0) { $0 + $1.score * $1.weight } / weight
        // Color is the steadiest cue; the right size and shape in the wrong color is not a match.
        let colorGate = colorScore(sample, expected: appearance.colors).map { 0.4 + 0.6 * $0 } ?? 1
        return blended * colorGate
    }

    static func score(classifierConfidence: Double?, appearanceScore: Double?, kind: AppearanceRegionKind,
                      weights: Weights = Weights()) -> Double {
        let classifier = classifierConfidence.map { min(1, $0 / weights.classifierCeiling) }
        var score: Double
        switch (classifier, appearanceScore) {
        case let (classifier?, appearance?): score = weights.classifier * classifier + (1 - weights.classifier) * appearance
        case let (classifier?, nil): score = classifier
        case let (nil, appearance?): score = appearance
        case (nil, nil): score = 0
        }
        if kind == .detection { score += weights.detectionBonus }
        return min(1, score)
    }
}

/// A region confirmed to match, smoothed across passes.
struct AppearanceMatch: Equatable, Sendable {
    var box: CGRect
    var score: Double
    var lastSeen: TimeInterval
    /// The image classifier agreed, not just color and texture; said with more confidence.
    var classifierBacked: Bool
}

/// Confirms a match only once it holds across passes, follows it as it moves, and keeps it through short
/// gaps: a hand reaching for the object hides it from the classifier just when guidance needs it most.
struct AppearanceMatchTracker {
    struct Configuration {
        /// Lowest score that counts, with classifier evidence behind it.
        var minimumScore = 0.5
        /// Color and texture alone are weaker evidence, so they need more.
        var appearanceOnlyScore = 0.65
        var confirmations = 2
        /// Two boxes are the same thing if their centers are this close (normalized) or they overlap.
        var sameCenterDistance: CGFloat = 0.15
        var holdDuration: TimeInterval = 3
        /// Weight of the newest box when following a match.
        var smoothing: CGFloat = 0.5
    }

    var configuration = Configuration()
    private(set) var match: AppearanceMatch?
    private var candidate: (box: CGRect, score: Double, hits: Int, lastSeen: TimeInterval, classified: Bool)?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func reset() {
        match = nil
        candidate = nil
    }

    /// - Parameter best: The best-scoring region of this pass, if any.
    @discardableResult
    mutating func update(best: ScoredRegion?, at time: TimeInterval) -> AppearanceMatch? {
        if let best, best.score >= threshold(for: best) {
            if var current = match, isSame(current.box, best.box) {
                current.box = blend(current.box, best.box)
                current.score = max(best.score, current.score * 0.8)
                current.lastSeen = time
                current.classifierBacked = current.classifierBacked || Self.classified(best)
                match = current
                candidate = nil
            } else if var pending = candidate, isSame(pending.box, best.box) {
                pending.box = blend(pending.box, best.box)
                pending.score = max(pending.score, best.score)
                pending.hits += 1
                pending.lastSeen = time
                pending.classified = pending.classified || Self.classified(best)
                candidate = pending
                if pending.hits >= configuration.confirmations {
                    match = AppearanceMatch(box: pending.box, score: pending.score, lastSeen: time,
                                            classifierBacked: pending.classified)
                    candidate = nil
                }
            } else {
                candidate = (best.box, best.score, 1, time, Self.classified(best))
            }
        }
        if let current = match, time - current.lastSeen > configuration.holdDuration { match = nil }
        if let pending = candidate, time - pending.lastSeen > configuration.holdDuration { candidate = nil }
        return match
    }

    private static func classified(_ region: ScoredRegion) -> Bool {
        (region.classifierConfidence ?? 0) >= 0.05
    }

    private func threshold(for region: ScoredRegion) -> Double {
        region.classifierConfidence == nil ? configuration.appearanceOnlyScore : configuration.minimumScore
    }

    private func isSame(_ a: CGRect, _ b: CGRect) -> Bool {
        hypot(a.midX - b.midX, a.midY - b.midY) <= configuration.sameCenterDistance || a.intersects(b)
    }

    private func blend(_ old: CGRect, _ new: CGRect) -> CGRect {
        let t = configuration.smoothing
        return CGRect(x: old.minX + (new.minX - old.minX) * t, y: old.minY + (new.minY - old.minY) * t,
                      width: old.width + (new.width - old.width) * t, height: old.height + (new.height - old.height) * t)
    }
}
