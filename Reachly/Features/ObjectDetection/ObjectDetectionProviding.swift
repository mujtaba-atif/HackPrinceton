import Foundation

/// Read-only output boundary for a future Core ML or Vision detector.
/// Pixel-buffer ingestion and inference are intentionally outside this foundation.
@MainActor
protocol ObjectDetectionProviding: AnyObject {
    var readiness: FeatureReadiness { get }
    var latestObjects: [DetectedObject] { get }

    func process(_ frame: CameraFrame) async
    func reset()
}

