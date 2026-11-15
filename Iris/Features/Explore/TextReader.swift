import Combine
import Vision

/// Continuously reads text from the middle of the camera view. Each scan feeds a sliding window
/// (see `TextConsolidator`), and `lines` is the clean, de-duplicated result.
final class TextReader: ObservableObject {
    /// The part of the frame that is read, as fractions of the image. Symmetric, so it doesn't depend on rotation.
    static let region = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    enum Recognition: Equatable { case searching, reading, ready }
    @Published private(set) var recognition: Recognition = .searching
    @Published private(set) var lines: [String] = []
    @Published private(set) var uprightImageSize = CGSize(width: 1440, height: 1920)

    private let scanInterval: TimeInterval
    private let minConfidence: Float = 0.3

    /// `TextConsolidator` reports a line once it has seen it in three of the last eight scans, so how
    /// often this runs is what sets how long someone has to hold an object still before anything is
    /// read — three scans at 2 Hz is a second and a half before the first word appears. Analyze runs it
    /// at 4 Hz for that reason; Find leaves it at 2, because there the OCR shares the frame with the
    /// segmenter and the hand pose.
    init(scanInterval: TimeInterval = 0.5) {
        self.scanInterval = scanInterval
    }

    private let queue = DispatchQueue(label: "com.iris.textreader", qos: .userInitiated)
    // Touched only on the main thread (the screens forward camera frames there).
    private var isBusy = false
    private var lastScan: TimeInterval = 0
    private var knowsImageSize = false
    /// Bumped by `reset`. A scan carries the value it started with, and its result is dropped if a reset
    /// happened while it was running — otherwise a rescan could get the previous item's text back.
    private var generation = 0
    // Touched only on `queue`.
    private var consolidator = TextConsolidator()
    private var readiness = RecognitionReadiness()

    /// Forgets everything read so far, so a rescan starts from an empty window.
    func reset() {
        generation += 1
        // Queued behind any scan already running, so it empties whatever that scan adds.
        queue.async { [weak self] in self?.consolidator.reset(); self?.readiness = RecognitionReadiness() }
        lines = []
        recognition = .searching
    }

    func process(frame: CameraFrame) {
        if !knowsImageSize {
            knowsImageSize = true
            let resolution = frame.imageResolution // landscape; the preview shows it rotated upright
            uprightImageSize = CGSize(width: resolution.height, height: resolution.width)
        }
        guard !isBusy, frame.timestamp - lastScan >= scanInterval else { return }
        isBusy = true
        lastScan = frame.timestamp
        // Keep only the pixel buffer, not the ARFrame, so ARKit's frame pool isn't starved.
        let pixelBuffer = frame.capturedImage
        let generation = generation
        queue.async { [weak self] in
            self?.scan(pixelBuffer, generation: generation)
            DispatchQueue.main.async { self?.isBusy = false }
        }
    }

    private func scan(_ pixelBuffer: CVPixelBuffer, generation: Int) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction can rewrite brand names and numbers; typos in ordinary words are easier to fix later.
        request.usesLanguageCorrection = false
        // Without this the recognizer may pick look-alike letters from other alphabets (a Cyrillic "м" in "mL").
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = Self.region

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try handler.perform([request])
        } catch {
            print("OCR error: \(error)")
            return
        }

        let readings: [TextReading] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= minConfidence else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 3, text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return TextReading(text: text, midY: observation.boundingBox.midY, minX: observation.boundingBox.minX)
        }

        consolidator.add(readings)
        let consolidated = consolidator.consolidated()
        let recognition = readiness.update(hasVisibleText: !readings.isEmpty, consolidated: consolidated)

        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.generation else { return }
            self.recognition = recognition
            guard consolidated != self.lines else { return }
            self.lines = consolidated
            if consolidated.isEmpty {
                print("OCR: no text")
            } else {
                print("OCR (\(consolidated.count) lines):")
                consolidated.forEach { print("  \($0)") }
            }
        }
    }
}

/// Recognition events, not a countdown: two matching consolidated OCR results make a read ready.
/// Empty camera results return to searching and require new evidence before another read is ready.
struct RecognitionReadiness {
    private var previous: [String] = []
    private var matchingScans = 0

    mutating func update(hasVisibleText: Bool, consolidated: [String]) -> TextReader.Recognition {
        guard hasVisibleText else {
            previous = []
            matchingScans = 0
            return .searching
        }
        guard !consolidated.isEmpty else { return .reading }
        matchingScans = consolidated == previous ? matchingScans + 1 : 1
        previous = consolidated
        return matchingScans >= 2 ? .ready : .reading
    }
}
