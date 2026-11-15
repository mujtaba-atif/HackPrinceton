import CoreGraphics
import Foundation
import Vision

enum TextRecognitionLevel: Sendable {
    /// Quick, lower-accuracy pass for live guidance.
    case fast
    /// Slower pass with language correction for the final read.
    case accurate
}

enum OCRError: LocalizedError, Equatable {
    case unreadableImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "The camera image could not be prepared for reading."
        case let .recognitionFailed(message): message
        }
    }
}

/// Reusable Vision text recognition on an already upright image.
/// Synchronous: call it from a background actor, never the main actor.
struct OCRService: Sendable {
    var recognitionLanguages = ["en-US"]

    /// - Returns: Lines with bounding boxes normalized to `image`, bottom-left origin.
    func recognizeText(in image: CGImage, level: TextRecognitionLevel) throws -> [RecognizedTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = level == .accurate
        request.recognitionLanguages = recognitionLanguages

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed(error.localizedDescription)
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RecognizedTextLine(text: text, confidence: Double(candidate.confidence),
                                      boundingBox: observation.boundingBox)
        }
    }
}
