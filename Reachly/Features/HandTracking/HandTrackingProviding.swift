import Foundation

/// Read-only output boundary for hand-pose observations. Future reach guidance consumes this.
/// Hand tracking owns no camera; its only input is the existing camera broker's frame stream.
@MainActor
protocol HandTrackingProviding: AnyObject {
    var readiness: FeatureReadiness { get }
    /// The latest smoothed hands, in upright normalized top-left image coordinates.
    var snapshot: HandTrackingSnapshot { get }
    /// The hand most worth guiding, if any.
    var primaryHand: HandObservation? { get }
    /// Compact projection onto the shared exploration model (focus point = pointing fingertip).
    var trackedHands: [TrackedHand] { get }

    func start(frames: AsyncStream<CameraFrame>)
    func stop()
    func process(_ frame: CameraFrame) async
    func reset()
}
