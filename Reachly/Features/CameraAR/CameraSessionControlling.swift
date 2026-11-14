import Foundation

enum CameraSessionState: Equatable, Sendable {
    case idle
    case preparing
    case running
    case stopped
    case failed(message: String)
}

/// Boundary for the future AVFoundation and ARKit implementation.
/// The foundation target intentionally provides no concrete camera session.
@MainActor
protocol CameraSessionControlling: AnyObject {
    var state: CameraSessionState { get }

    func prepare() async throws
    func stop()
}

