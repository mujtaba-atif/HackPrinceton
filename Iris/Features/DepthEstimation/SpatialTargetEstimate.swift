import Foundation
import simd

enum HorizontalPosition: String, Equatable, Sendable {
    case left, center, right, unknown
}

enum VerticalPosition: String, Equatable, Sendable {
    case above, center, below, unknown
}

enum DepthUnavailableReason: Equatable, Sendable {
    case unsupportedDevice
    case waitingForDepth
    case missingDepth
    case lowConfidence
    case inconsistentDepth
    case invalidGeometry
    case unmatchedFrame
    case staleObservation
    case targetLost
    case trackingLimited
    case cameraPaused

    var message: String {
        switch self {
        case .unsupportedDevice: "This device does not support LiDAR scene depth."
        case .waitingForDepth: "Waiting for a depth measurement."
        case .missingDepth: "The camera has no depth measurement."
        case .lowConfidence: "There are too few confident depth samples."
        case .inconsistentDepth: "Depth readings vary too much in this region."
        case .invalidGeometry: "The object's position could not be measured."
        case .unmatchedFrame: "No depth frame matches this observation."
        case .staleObservation: "Waiting for a recent object observation."
        case .targetLost: "The selected object is no longer tracked."
        case .trackingLimited: "Camera tracking is limited. Hold the phone steady."
        case .cameraPaused: "The camera is paused."
        }
    }
}

enum SpatialMeasurementValidity: Equatable, Sendable {
    case measured
    case unavailable(DepthUnavailableReason)
}

/// A camera-relative estimate of the selected box's central surface, not an object pose or anchor.
/// Timestamp is the originating ARFrame time for measured results. Consumers must check age/validity.
struct SpatialTargetEstimate: Equatable, Sendable {
    let objectID: UUID
    let distanceMeters: Double?
    let horizontalPosition: HorizontalPosition
    let verticalPosition: VerticalPosition
    let horizontalAngleRadians: Double?
    let verticalAngleRadians: Double?
    /// Portrait camera axes: +X right, +Y up, +Z forward, in meters. Not ARKit world coordinates.
    let positionInPortraitCameraMeters: SIMD3<Double>?
    let validity: SpatialMeasurementValidity
    let timestamp: TimeInterval

    static func unavailable(objectID: UUID, reason: DepthUnavailableReason, timestamp: TimeInterval) -> Self {
        .init(objectID: objectID, distanceMeters: nil,
              horizontalPosition: .unknown, verticalPosition: .unknown,
              horizontalAngleRadians: nil, verticalAngleRadians: nil,
              positionInPortraitCameraMeters: nil, validity: .unavailable(reason), timestamp: timestamp)
    }
}

@MainActor
protocol DepthEstimationProviding: AnyObject {
    var estimate: SpatialTargetEstimate? { get }
    func start(frames: AsyncStream<CameraFrame>, supportsSceneDepth: Bool)
    func setTarget(_ target: SelectedObjectTarget?)
    func stop()
}
