import Foundation

/// Read-only output boundary for future hand-pose observations.
@MainActor
protocol HandTrackingProviding: AnyObject {
    var readiness: FeatureReadiness { get }
    var trackedHands: [TrackedHand] { get }

    func process(_ frame: CameraFrame) async
    func reset()
}

