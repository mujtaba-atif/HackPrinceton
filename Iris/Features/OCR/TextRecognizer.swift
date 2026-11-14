import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Serial actor keeps synchronous Vision text recognition off the main actor.
/// It only reads pixel buffers handed to it; it never owns or starts a camera.
actor TextRecognizer {
    static let minimumConfidence: Float = 0.3

    /// - Parameter region: Vision coordinates (normalized, bottom-left origin) in the upright image.
    func recognize(_ image: CVPixelBuffer, region: CGRect) throws -> [RecognizedTextLine] {
        try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.regionOfInterest = region
            // Iris locks its rear-camera UI to portrait; native AR buffers are landscape.
            let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .right)
            try handler.perform([request])

            let lines: [RecognizedTextLine] = (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= Self.minimumConfidence else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2, text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
                // Results are relative to the region of interest; map back to the full image.
                let box = observation.boundingBox
                let full = CGRect(x: region.minX + box.minX * region.width,
                                  y: region.minY + box.minY * region.height,
                                  width: box.width * region.width, height: box.height * region.height)
                return RecognizedTextLine(text: text, confidence: Double(candidate.confidence), boundingBox: full)
            }
            return OCRGeometry.readingOrder(lines)
        }
    }
}
