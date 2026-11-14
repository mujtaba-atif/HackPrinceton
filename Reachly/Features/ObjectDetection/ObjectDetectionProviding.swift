import Foundation

/// Detection owns no camera. Its only input is the existing camera broker's frame stream.
@MainActor
protocol ObjectDetectionProviding: AnyObject {
    var readiness: FeatureReadiness { get }
    var latestObjects: [DetectedObject] { get }
    var selectedTarget: SelectedObjectTarget? { get }

    func start(frames: AsyncStream<CameraFrame>)
    func stop()
    func process(_ frame: CameraFrame) async
    func select(_ id: UUID)
    func clearSelection()
    func reset()
}

