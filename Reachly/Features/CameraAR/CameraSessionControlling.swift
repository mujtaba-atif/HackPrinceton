import Foundation

enum CameraUnavailableReason: Equatable, Sendable {
    case permissionDenied
    case permissionRestricted
    case noRearCamera
    case arKitUnsupported

    var title: String {
        switch self {
        case .permissionDenied: "Camera access is off"
        case .permissionRestricted: "Camera access is restricted"
        case .noRearCamera: "Rear camera unavailable"
        case .arKitUnsupported: "AR is unavailable"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied:
            "Allow camera access in Settings to use Reachly’s live exploration view."
        case .permissionRestricted:
            "This device currently prevents apps from using the camera."
        case .noRearCamera:
            "Reachly could not find a rear camera on this device."
        case .arKitUnsupported:
            "This device does not support the AR tracking Reachly needs for exploration."
        }
    }

    var canOpenSettings: Bool {
        self == .permissionDenied
    }
}

enum CameraSessionState: Equatable, Sendable {
    case idle
    case requestingPermission
    case preparing
    case running
    case paused
    case interrupted
    case stopped
    case unavailable(reason: CameraUnavailableReason)
    case failed(message: String)
}

/// Owns the one active camera session and exposes a fan-out stream of recent frames.
/// Future computer-vision services subscribe to this stream instead of starting cameras of their own.
@MainActor
protocol CameraSessionControlling: AnyObject {
    var state: CameraSessionState { get }

    func start() async
    func pause()
    func stop()
    func makeFrameStream() -> AsyncStream<CameraFrame>
}

