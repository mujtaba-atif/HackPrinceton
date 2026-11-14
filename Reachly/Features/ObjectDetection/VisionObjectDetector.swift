import CoreML
import Vision
import CoreVideo
import Foundation

enum ObjectDetectionError: LocalizedError {
    case missingModel
    case incompatibleModel
    case unexpectedResults

    var errorDescription: String? {
        switch self {
        case .missingModel: "The object detection model is missing from this app. Reinstall Reachly."
        case .incompatibleModel: "The bundled model is not a compatible object detector."
        case .unexpectedResults: "The detector returned an unsupported result format."
        }
    }
}

/// Serial actor keeps model loading and synchronous Vision inference off the main actor.
/// The compiled model includes class labels and non-maximum suppression.
actor VisionObjectDetector {
    private var request: VNCoreMLRequest?

    func prepare(modelURL: URL? = Bundle.main.url(forResource: "YOLOv3TinyFP16", withExtension: "mlmodelc")) throws {
        guard request == nil else { return }
        guard let modelURL else { throw ObjectDetectionError.missingModel }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["image"]?.type == .image,
              model.modelDescription.outputDescriptionsByName["coordinates"] != nil,
              model.modelDescription.outputDescriptionsByName["confidence"] != nil else {
            throw ObjectDetectionError.incompatibleModel
        }
        let visionModel = try VNCoreMLModel(for: model)
        // Supply explicit thresholds to the model's built-in NMS stage.
        visionModel.featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "confidenceThreshold": 0.35, "iouThreshold": 0.45
        ])
        let request = VNCoreMLRequest(model: visionModel)
        // Resize the whole upright image to 416x416. No letterbox/crop offsets to undo.
        request.imageCropAndScaleOption = .scaleFill
        self.request = request
    }

    func detect(_ image: CVPixelBuffer) throws -> [ObjectCandidate] {
        guard let request else { throw ObjectDetectionError.missingModel }
        return try autoreleasepool {
            // Reachly locks its rear-camera UI to portrait. Native AR buffers are landscape.
            let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .right)
            try handler.perform([request])
            guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                throw ObjectDetectionError.unexpectedResults
            }
            return observations.compactMap { observation in
                guard let label = observation.labels.first, label.confidence >= 0.35,
                      let box = DetectionGeometry.clippedUnitRect(observation.boundingBox) else { return nil }
                return ObjectCandidate(name: label.identifier, confidence: Double(label.confidence),
                                       boundingBox: box)
            }
        }
    }
}
