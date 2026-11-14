import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// One unsmoothed hand from a single frame. Points are upright normalized top-left image space.
struct RawHandPose: Equatable, Sendable {
    let chirality: HandChirality
    let landmarks: [HandJoint: HandLandmark]
}

enum HandTrackingError: LocalizedError {
    case unexpectedResults

    var errorDescription: String? {
        switch self {
        case .unexpectedResults: "The hand pose detector returned an unsupported result format."
        }
    }
}

/// Serial actor keeps synchronous Vision inference off the main actor.
/// It only reads pixel buffers handed to it; it never owns or starts a camera.
actor VisionHandPoseDetector {
    static let minimumJointConfidence: Float = 0.3

    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    func detect(_ image: CVPixelBuffer) throws -> [RawHandPose] {
        try autoreleasepool {
            // Iris locks its rear-camera UI to portrait; native AR buffers are landscape.
            let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .right)
            try handler.perform([request])
            guard let observations = request.results else { throw HandTrackingError.unexpectedResults }
            return observations.compactMap(Self.rawPose(from:))
        }
    }

    private static func rawPose(from observation: VNHumanHandPoseObservation) -> RawHandPose? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        var landmarks: [HandJoint: HandLandmark] = [:]
        for joint in HandJoint.allCases {
            guard let point = points[joint.visionName],
                  point.confidence >= minimumJointConfidence else { continue }
            let location = HandGeometry.visionToImage(point.location)
            guard HandGeometry.isValidNormalized(location) else { continue }
            landmarks[joint] = HandLandmark(joint: joint, location: location, confidence: Double(point.confidence))
        }
        guard !landmarks.isEmpty else { return nil }
        return RawHandPose(chirality: HandChirality(observation.chirality), landmarks: landmarks)
    }
}

private extension HandChirality {
    init(_ chirality: VNChirality) {
        switch chirality {
        case .left: self = .left
        case .right: self = .right
        default: self = .unknown
        }
    }
}

private extension HandJoint {
    var visionName: VNHumanHandPoseObservation.JointName {
        switch self {
        case .wrist: .wrist
        case .thumbCMC: .thumbCMC
        case .thumbMP: .thumbMP
        case .thumbIP: .thumbIP
        case .thumbTip: .thumbTip
        case .indexMCP: .indexMCP
        case .indexPIP: .indexPIP
        case .indexDIP: .indexDIP
        case .indexTip: .indexTip
        case .middleMCP: .middleMCP
        case .middlePIP: .middlePIP
        case .middleDIP: .middleDIP
        case .middleTip: .middleTip
        case .ringMCP: .ringMCP
        case .ringPIP: .ringPIP
        case .ringDIP: .ringDIP
        case .ringTip: .ringTip
        case .littleMCP: .littleMCP
        case .littlePIP: .littlePIP
        case .littleDIP: .littleDIP
        case .littleTip: .littleTip
        }
    }
}
