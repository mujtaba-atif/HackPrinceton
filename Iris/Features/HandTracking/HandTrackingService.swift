import Combine
import CoreGraphics
import CoreVideo
import Foundation

/// Subscribes to `CameraFrameBroker` frames, runs Vision hand pose off the main actor,
/// and publishes smoothed, identity-stable hands. It never creates or controls a camera session.
@MainActor
final class HandTrackingService: ObservableObject, HandTrackingProviding {
    /// ~15 Hz is plenty for reach guidance and leaves headroom for object detection.
    static let minimumFrameInterval: TimeInterval = 1.0 / 15.0
    /// Frames older than this are skipped rather than processed late.
    static let maximumFrameAge: TimeInterval = 0.25

    @Published private(set) var readiness: FeatureReadiness = .planned
    @Published private(set) var snapshot = HandTrackingSnapshot()

    var primaryHand: HandObservation? { snapshot.primaryHand }

    var trackedHands: [TrackedHand] {
        snapshot.hands.compactMap { hand in
            guard hand.state == .tracking || hand.state == .limited else { return nil }
            let focus = hand.pointingTip ?? hand.center
            return TrackedHand(id: hand.id, side: HandSide(hand.chirality),
                               focusPoint: NormalizedPoint(x: focus.x, y: focus.y))
        }
    }

    private let detector = VisionHandPoseDetector()
    private var reducer = HandTrackingReducer()
    private var consumer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = UUID()
    private var inFlight = false
    private var lastProcessedTimestamp: TimeInterval?
    private var isRunning = false

    func start(frames: AsyncStream<CameraFrame>) {
        stop()
        isRunning = true
        readiness = .ready
        reducer.resume()
        publish()
        let run = generation

        // Sequential consumption plus the broker's bufferingNewest(1) bounds retained work to one frame.
        consumer = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self, self.generation == run else { return }
                await self.process(frame)
                if case .unavailable = self.readiness { return }
            }
            guard let self, self.generation == run, !Task.isCancelled else { return }
            self.stop()
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, self.generation == run else { return }
                self.reducer.expire(at: ProcessInfo.processInfo.systemUptime)
                self.publish()
            }
        }
    }

    func process(_ frame: CameraFrame) async {
        let now = ProcessInfo.processInfo.systemUptime
        guard isRunning, readiness == .ready, !inFlight,
              now - frame.timestamp < Self.maximumFrameAge,
              lastProcessedTimestamp.map({ frame.timestamp - $0 >= Self.minimumFrameInterval }) ?? true else { return }
        inFlight = true
        lastProcessedTimestamp = frame.timestamp
        let run = generation
        defer { inFlight = false }

        do {
            let poses = try await detector.detect(frame.capturedImage)
            guard run == generation, isRunning, !Task.isCancelled else { return }
            let bufferSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage),
                                    height: CVPixelBufferGetHeight(frame.capturedImage))
            reducer.update(poses, timestamp: frame.timestamp,
                           imageSize: HandGeometry.uprightSize(forBufferSize: bufferSize))
            publish()
        } catch {
            guard run == generation, isRunning, !Task.isCancelled else { return }
            fail(error)
        }
    }

    func stop() {
        generation = UUID()
        isRunning = false
        consumer?.cancel()
        watchdog?.cancel()
        consumer = nil
        watchdog = nil
        lastProcessedTimestamp = nil
        // Do not clear inFlight: a synchronous Vision request may still be finishing.
        reducer.suspend()
        publish()
        readiness = .planned
    }

    func reset() {
        stop()
        reducer = HandTrackingReducer()
        publish()
    }

    private func fail(_ error: Error) {
        stop()
        readiness = .unavailable(reason: "Hand tracking is unavailable. " + error.localizedDescription)
    }

    private func publish() {
        if snapshot != reducer.snapshot { snapshot = reducer.snapshot }
    }

    deinit {
        consumer?.cancel()
        watchdog?.cancel()
    }
}

private extension HandSide {
    init(_ chirality: HandChirality) {
        switch chirality {
        case .left: self = .left
        case .right: self = .right
        case .unknown: self = .unknown
        }
    }
}
