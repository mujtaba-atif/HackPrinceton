import ARKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class IrisCameraController: NSObject, ObservableObject, CameraSessionControlling {
    @Published private(set) var state: CameraSessionState = .idle

    let session: ARSession
    let supportsSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    private let frameBroker: CameraFrameBroker
    private let delegateProxy: ARSessionDelegateProxy
    private var hasRun = false
    private var shouldResumeAfterLifecyclePause = false
    private var startRequestID: UUID?

    override init() {
        let session = ARSession()
        let frameBroker = CameraFrameBroker()
        let delegateProxy = ARSessionDelegateProxy(frameBroker: frameBroker)

        self.session = session
        self.frameBroker = frameBroker
        self.delegateProxy = delegateProxy

        super.init()

        delegateProxy.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        session.delegate = delegateProxy
        session.delegateQueue = DispatchQueue(
            label: "com.iris.camera.ar-session",
            qos: .userInitiated
        )
    }

    func start() async {
        guard state != .running, startRequestID == nil else { return }

        let requestID = UUID()
        startRequestID = requestID
        defer {
            if startRequestID == requestID {
                startRequestID = nil
            }
        }

        guard ARWorldTrackingConfiguration.isSupported else {
            state = .unavailable(reason: .arKitUnsupported)
            return
        }

        guard AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) != nil else {
            state = .unavailable(reason: .noRearCamera)
            return
        }

        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        let resolvedPermission: AVAuthorizationStatus

        if permission == .notDetermined {
            state = .requestingPermission
            resolvedPermission = await requestCameraPermission()
        } else {
            resolvedPermission = permission
        }

        guard startRequestID == requestID, !Task.isCancelled else { return }

        switch resolvedPermission {
        case .authorized:
            break
        case .denied:
            state = .unavailable(reason: .permissionDenied)
            return
        case .restricted:
            state = .unavailable(reason: .permissionRestricted)
            return
        case .notDetermined:
            state = .failed(message: "Camera permission could not be determined.")
            return
        @unknown default:
            state = .failed(message: "Camera permission returned an unknown status.")
            return
        }

        state = .preparing

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none

        if supportsSceneDepth {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        let options: ARSession.RunOptions = hasRun
            ? []
            : [.resetTracking, .removeExistingAnchors]

        session.run(configuration, options: options)
        hasRun = true
        shouldResumeAfterLifecyclePause = false
        state = .running
    }

    func pause() {
        invalidatePendingStart()
        shouldResumeAfterLifecyclePause = false

        guard state == .running || state == .interrupted else { return }
        session.pause()
        state = .paused
    }

    func stop() {
        invalidatePendingStart()
        shouldResumeAfterLifecyclePause = false
        session.pause()
        hasRun = false
        state = .stopped
    }

    func makeFrameStream() -> AsyncStream<CameraFrame> {
        frameBroker.makeStream()
    }

    /// Pauses capture when the app leaves the foreground and remembers whether it should resume.
    func pauseForAppLifecycle() {
        guard state == .running else { return }
        shouldResumeAfterLifecyclePause = true
        session.pause()
        state = .paused
    }

    /// Refreshes permission after Settings and resumes only a lifecycle-paused camera.
    func resumeAfterAppLifecyclePause() async {
        if case let .unavailable(reason) = state,
           reason == .permissionDenied || reason == .permissionRestricted,
           AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            state = .idle
        }

        guard shouldResumeAfterLifecyclePause else { return }
        shouldResumeAfterLifecyclePause = false
        await start()
    }

    private func requestCameraPermission() async -> AVAuthorizationStatus {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .authorized : .denied
    }

    private func invalidatePendingStart() {
        startRequestID = nil
    }

    private func handle(_ event: ARSessionDelegateProxy.Event) {
        guard state != .stopped else { return }

        switch event {
        case let .failed(message):
            shouldResumeAfterLifecyclePause = false
            session.pause()
            hasRun = false
            state = .failed(message: message)
        case .interrupted:
            guard state == .running else { return }
            shouldResumeAfterLifecyclePause = false
            state = .interrupted
        case .interruptionEnded:
            guard state == .interrupted else { return }
            state = .paused
        }
    }
}

private final class ARSessionDelegateProxy: NSObject, ARSessionDelegate {
    enum Event {
        case failed(message: String)
        case interrupted
        case interruptionEnded
    }

    var onEvent: ((Event) -> Void)?

    private let frameBroker: CameraFrameBroker

    init(frameBroker: CameraFrameBroker) {
        self.frameBroker = frameBroker
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameBroker.publish(CameraFrame(arFrame: frame))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onEvent?(.failed(message: error.localizedDescription))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onEvent?(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        onEvent?(.interruptionEnded)
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }
}

