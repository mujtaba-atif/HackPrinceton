import Foundation
import Combine

@MainActor
final class DepthEstimationService: ObservableObject, DepthEstimationProviding {
    @Published private(set) var estimate: SpatialTargetEstimate?
    private var target: SelectedObjectTarget?
    private var consumer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = UUID()
    private var isRunning = false
    private var supportsSceneDepth = false

    func start(frames: AsyncStream<CameraFrame>, supportsSceneDepth: Bool) {
        stop()
        self.supportsSceneDepth = supportsSceneDepth
        isRunning = true
        invalidate(.waitingForDepth)
        let run = generation
        // New state per run prevents cached buffers and smoothing crossing camera restarts.
        let worker = DepthEstimationWorker()
        consumer = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self, self.generation == run else { return }
                let now = ProcessInfo.processInfo.systemUptime
                guard now - frame.timestamp >= 0,
                      now - frame.timestamp <= DepthEstimationProcessor.maximumAge else {
                    self.invalidate(.staleObservation)
                    continue
                }
                let target = self.target
                let result = await worker.process(DepthFrame(cameraFrame: frame), target: target,
                                                  supportsSceneDepth: supportsSceneDepth)
                guard !Task.isCancelled, self.generation == run, self.target == target else { continue }
                if let result, ProcessInfo.processInfo.systemUptime - result.timestamp > DepthEstimationProcessor.maximumAge {
                    self.invalidate(.staleObservation)
                } else {
                    self.publish(result)
                }
            }
            guard let self, self.generation == run, !Task.isCancelled else { return }
            self.stop()
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.generation == run else { return }
                if let estimate = self.estimate,
                   estimate.distanceMeters != nil || estimate.horizontalAngleRadians != nil,
                   ProcessInfo.processInfo.systemUptime - estimate.timestamp > DepthEstimationProcessor.maximumAge {
                    self.invalidate(.staleObservation)
                }
            }
        }
    }

    func setTarget(_ target: SelectedObjectTarget?) {
        let identityChanged = self.target?.object.id != target?.object.id
        let stateChanged = self.target?.state != target?.state
        self.target = target
        guard let target else {
            publish(nil)
            return
        }
        if target.state == .lost {
            invalidate(.targetLost)
        } else if !isRunning {
            invalidate(.cameraPaused)
        } else if !supportsSceneDepth {
            invalidate(.unsupportedDevice)
        } else if identityChanged || stateChanged || estimate == nil {
            invalidate(.waitingForDepth)
        }
        // Same target's previous measurement remains usable only until its own 500 ms expiry.
        // The next broker frame measures the new observation against cached depth.
    }

    func stop() {
        generation = UUID()
        isRunning = false
        consumer?.cancel()
        watchdog?.cancel()
        consumer = nil
        watchdog = nil
        invalidate(.cameraPaused)
    }

    private func invalidate(_ reason: DepthUnavailableReason) {
        publish(target.map {
            .unavailable(objectID: $0.object.id, reason: reason, timestamp: $0.lastSeenTimestamp)
        })
    }

    private func publish(_ value: SpatialTargetEstimate?) {
        if estimate != value { estimate = value }
    }

    deinit {
        consumer?.cancel()
        watchdog?.cancel()
    }
}
