import CoreGraphics
import Foundation

/// A detected object described in user-relative terms.
struct VisibleObject: Equatable, Sendable {
    let id: UUID
    let name: String
    let confidence: Double
    /// "on your left", "ahead", or "on your right", from the box's horizontal center.
    let position: String

    init(_ object: DetectedObject) {
        id = object.id
        name = object.name
        confidence = object.confidence
        position = Self.position(forMidX: object.boundingBox.midX)
    }

    static func position(forMidX x: CGFloat) -> String {
        switch x {
        case ..<0.33: "on your left"
        case 0.67...: "on your right"
        default: "ahead"
        }
    }

    var confidenceWord: String {
        switch confidence {
        case 0.75...: "likely"
        case 0.5..<0.75: "possibly"
        default: "maybe"
        }
    }
}

/// Everything the assistant is allowed to know: only real detections and real OCR output.
struct AssistantContext: Equatable, Sendable {
    var isCameraRunning: Bool
    var objects: [VisibleObject]
    var selected: SelectedObjectTarget?
    var ocr: OCRResult?

    init(isCameraRunning: Bool, snapshot: DetectionSnapshot, ocr: OCRResult?) {
        self.isCameraRunning = isCameraRunning
        objects = snapshot.objects.sorted { $0.confidence > $1.confidence }.map(VisibleObject.init)
        selected = snapshot.selectedTarget
        self.ocr = ocr
    }

    static let empty = AssistantContext(isCameraRunning: false, snapshot: DetectionSnapshot(), ocr: nil)
}
