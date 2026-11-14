import Foundation
import CoreGraphics

/// Bounds use Vision coordinates: normalized full upright portrait image, bottom-left origin.
/// IDs persist through spatially overlapping detections of the same class; they are not identities.
struct DetectedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let confidence: Double
    let boundingBox: CGRect

    var region: NormalizedRegion {
        NormalizedRegion(origin: .init(x: boundingBox.minX, y: boundingBox.minY),
                         width: boundingBox.width, height: boundingBox.height)
    }
}

struct ObjectCandidate: Equatable, Sendable {
    let name: String
    let confidence: Double
    let boundingBox: CGRect
}

enum ObjectTrackingState: Equatable, Sendable {
    case tracking
    case lost
}

/// Future guidance must use currentBoundingBox, and pair lastSeenTimestamp with a camera frame.
/// A lost target keeps its identity and last observation, but never exposes a current box.
struct SelectedObjectTarget: Equatable, Sendable {
    let object: DetectedObject
    let state: ObjectTrackingState
    let lastSeenTimestamp: TimeInterval
    let uprightImageSize: CGSize

    var currentBoundingBox: CGRect? { state == .tracking ? object.boundingBox : nil }
    var sensorBoundingBox: CGRect? {
        currentBoundingBox.map(DetectionGeometry.sensorRect)
    }
}

struct DetectionSnapshot: Equatable, Sendable {
    var objects: [DetectedObject] = []
    var selectedTarget: SelectedObjectTarget?
    var timestamp: TimeInterval?
    var uprightImageSize: CGSize = .zero
}
