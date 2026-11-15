import Combine
import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation
import SwiftUI
import Vision

/// Looks for regions of a camera frame matching a `TargetAppearance`, off the main actor.
///
/// Each pass proposes regions three ways: detections of the appearance's detector classes, Vision's
/// class-agnostic objectness saliency ("something is here"), and a 3 × 3 grid of windows so that small
/// things nothing else proposes are still looked at. Each region is then scored by Apple's on-device
/// image classifier against the appearance's labels, and by its color, texture, shape and size.
actor AppearanceScanner {
    /// Upright working image for color and texture, longest side in pixels.
    static let sampleLongSide: CGFloat = 320
    /// The classifier needs some context; smaller regions are grown to at least this size around their center.
    static let minimumClassifierRegion: CGFloat = 0.18

    private let context = CIContext(options: [.cacheIntermediates: false])
    /// After a classifier failure, color and texture carry the search until this time, then it tries again.
    private var classifierRetryAt: TimeInterval = 0

    /// The identifiers Apple's classifier can return, read once.
    static let classifierLabels: Set<String> = {
        (try? VNClassifyImageRequest().supportedIdentifiers()).map(Set.init) ?? []
    }()

    /// - Parameter detections: Boxes of detections whose class is one of the appearance's detector classes.
    func scan(pixelBuffer: CVPixelBuffer, appearance: TargetAppearance, detections: [CGRect]) -> [ScoredRegion] {
        autoreleasepool {
            var regions = detections.map { ($0, AppearanceRegionKind.detection) }
            regions += salientRegions(in: pixelBuffer).map { ($0, .salient) }
            if !appearance.classifierLabels.isEmpty {
                regions += Self.tiles.map { ($0, .tile) }
            }
            guard !regions.isEmpty, let bitmap = bitmap(from: pixelBuffer) else { return [] }
            let confidences = classify(regions.map { $0.0 }, in: pixelBuffer, labels: appearance.classifierLabels)

            return bitmap.pixels.withUnsafeBufferPointer { pixels in
                regions.enumerated().map { index, entry in
                    let (box, kind) = entry
                    let appearanceScore = AppearanceAnalyzer.sample(
                        rgba: pixels, width: bitmap.width, height: bitmap.height,
                        bytesPerRow: bitmap.width * 4, region: box
                    ).flatMap {
                        AppearanceAnalyzer.appearanceScore($0, box: box, kind: kind, appearance: appearance,
                                                           imageAspect: Double(bitmap.width) / Double(bitmap.height))
                    }
                    let confidence = confidences?[index]
                    return ScoredRegion(box: box, kind: kind, classifierConfidence: confidence,
                                        appearanceScore: appearanceScore,
                                        score: AppearanceAnalyzer.score(classifierConfidence: confidence,
                                                                        appearanceScore: appearanceScore, kind: kind))
                }
                .sorted { $0.score > $1.score }
            }
        }
    }

    static let tiles: [CGRect] = (0..<3).flatMap { row in
        (0..<3).map { column in
            CGRect(x: CGFloat(column) / 3, y: CGFloat(row) / 3, width: 1.0 / 3, height: 1.0 / 3)
        }
    }

    // MARK: Proposals

    private func salientRegions(in pixelBuffer: CVPixelBuffer) -> [CGRect] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNSaliencyImageObservation else { return [] }
        return (observation.salientObjects ?? [])
            .map(\.boundingBox)
            .filter { $0.width * $0.height >= 0.0015 && $0.width * $0.height <= 0.6 }
            .prefix(4)
            .map { $0 }
    }

    // MARK: Classifier

    /// Best confidence among `labels` for each region, or nil if the classifier can't run (e.g. no
    /// Neural Engine in the simulator) or there are no labels to look for.
    private func classify(_ regions: [CGRect], in pixelBuffer: CVPixelBuffer, labels: [String]) -> [Double]? {
        guard !labels.isEmpty, ProcessInfo.processInfo.systemUptime >= classifierRetryAt else { return nil }
        let wanted = Set(labels)
        let requests = regions.map { region -> VNClassifyImageRequest in
            let request = VNClassifyImageRequest()
            request.regionOfInterest = Self.classifierRegion(for: region)
            return request
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform(requests)
        } catch {
            classifierRetryAt = ProcessInfo.processInfo.systemUptime + 10
            print("Appearance search: classifier unavailable, using color and texture for now (\(error))")
            return nil
        }
        return requests.map { request in
            Double((request.results ?? []).filter { wanted.contains($0.identifier) }.map(\.confidence).max() ?? 0)
        }
    }

    static func classifierRegion(for box: CGRect) -> CGRect {
        let width = max(box.width, minimumClassifierRegion), height = max(box.height, minimumClassifierRegion)
        let grown = CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
        return grown.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: Pixels

    private struct Bitmap {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    /// The whole upright frame, small, as RGBA8 with row 0 at the top.
    private func bitmap(from pixelBuffer: CVPixelBuffer) -> Bitmap? {
        let upright = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let extent = upright.extent
        let scale = min(1, Self.sampleLongSide / max(extent.width, extent.height))
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = scaled.extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(scaled, toBitmap: buffer.baseAddress!, rowBytes: width * 4, bounds: bounds,
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return Bitmap(pixels: pixels, width: width, height: height)
    }
}

/// Runs `AppearanceScanner` on the shared camera's frames while Locate is looking for something the
/// object detector can't find by itself, and publishes the confirmed match.
@MainActor
final class AppearanceSearch: ObservableObject {
    @Published private(set) var appearance: TargetAppearance?
    @Published private(set) var match: AppearanceMatch?
    /// The upright camera image size, for drawing the match over the preview.
    @Published private(set) var uprightImageSize: CGSize = .zero

    /// Seconds between passes; each pass classifies up to about 16 regions.
    var passInterval: TimeInterval = 0.4
    private let scanner = AppearanceScanner()
    private var tracker = AppearanceMatchTracker()
    private var task: Task<Void, Never>?

    var isActive: Bool { task != nil }

    /// - Parameter detections: The detector's current objects; those of the appearance's detector classes
    ///   are searched as regions.
    func start(_ appearance: TargetAppearance, frames: AsyncStream<CameraFrame>,
               detections: @escaping @MainActor () -> [DetectedObject]) {
        stop()
        self.appearance = appearance
        let classes = Set(appearance.detectorClasses)
        print("Appearance search: \(appearance.name) — labels \(appearance.classifierLabels), look \(appearance.spokenLook)")
        task = Task { [weak self] in
            var lastPass: TimeInterval = -.infinity
            for await frame in frames {
                guard !Task.isCancelled, let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastPass >= self.passInterval, now - frame.timestamp <= 0.5 else { continue }
                lastPass = now
                let size = CGSize(width: CVPixelBufferGetHeight(frame.capturedImage),
                                  height: CVPixelBufferGetWidth(frame.capturedImage))
                if self.uprightImageSize != size { self.uprightImageSize = size }
                let boxes = detections().filter { classes.contains($0.name) }.map(\.boundingBox)
                let regions = await self.scanner.scan(pixelBuffer: frame.capturedImage, appearance: appearance,
                                                      detections: boxes)
                guard !Task.isCancelled else { return }
                let match = self.tracker.update(best: regions.first, at: now)
                if self.match != match { self.match = match }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        tracker.reset()
        match = nil
        appearance = nil
    }
}

/// Outlines the appearance match over the camera preview, the way the detection overlay outlines a detection.
struct AppearanceMatchOverlay: View {
    let match: AppearanceMatch?
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            if let match, imageSize.width > 0 {
                let rect = DetectionGeometry.viewRect(match.box, imageSize: imageSize, viewport: geometry.size)
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .animation(.easeInOut(duration: 0.25), value: match.box)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What Locate says while searching by appearance. Never any of `LocateScreen.backKeywords`: the
/// microphone hears the speaker.
enum AppearanceSearchPhrases {
    static func thinking(about name: String) -> String {
        "Let me think about what \(AssistantFacts.a(name)) looks like."
    }

    /// Said once the search starts: why it's different, and what it is looking for.
    static func searching(for appearance: TargetAppearance) -> String {
        let look = appearance.spokenLook
        let lookPart = look.isEmpty ? "" : ", something \(look)"
        return "I don't have a detector trained for \(appearance.name), so I'll look for it by sight\(lookPart). "
            + "Move the camera slowly over where it might be."
    }

    /// Said when a match is first confirmed. Color and texture alone can be fooled, so it says so.
    static func found(_ name: String, match: AppearanceMatch) -> String {
        let place = VisibleObject.position(forMidX: match.box.midX)
        if match.classifierBacked, match.score >= 0.7 {
            return "I think I see the \(name), \(place)."
        }
        return "This might be the \(name), \(place). I'm going by how it looks, so check it by touch."
    }

    static func unknown(_ name: String) -> String {
        "I don't know what \(name) looks like. Tell me its color and size, like a small blue box."
    }
}
