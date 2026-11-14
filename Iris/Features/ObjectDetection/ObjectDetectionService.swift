import Foundation
import Combine
import CoreVideo

@MainActor
final class ObjectDetectionService: ObservableObject, ObjectDetectionProviding {
    @Published private(set) var readiness: FeatureReadiness = .planned
    @Published private(set) var snapshot = DetectionSnapshot()

    var latestObjects: [DetectedObject] { snapshot.objects }
    var selectedTarget: SelectedObjectTarget? { snapshot.selectedTarget }

    private let detector = VisionObjectDetector()
    private var state = ObjectDetectionState()
    private var consumer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var generation = UUID()
    private var inFlight = false
    private var lastProcessedTimestamp: TimeInterval?
    private var isRunning = false

    func start(frames: AsyncStream<CameraFrame>) {
        stop()
        isRunning = true
        readiness = .preparing
        let run = generation
        consumer = Task { [weak self, detector] in
            do {
                try await detector.prepare()
                guard let self, self.generation == run, !Task.isCancelled else { return }
                self.readiness = .ready
            } catch {
                guard let self, self.generation == run, !Task.isCancelled else { return }
                self.fail(error)
                return
            }
            // Sequential consumption plus bufferingNewest(1) bounds retained work to one new frame.
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
                self.state.expire(at: ProcessInfo.processInfo.systemUptime)
                self.publish()
            }
        }
    }

    func process(_ frame: CameraFrame) async {
        guard isRunning, readiness == .ready, !inFlight,
              ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.25,
              lastProcessedTimestamp.map({ frame.timestamp - $0 >= 0.125 }) ?? true else { return }
        inFlight = true
        lastProcessedTimestamp = frame.timestamp
        let run = generation
        defer { inFlight = false }
        do {
            let candidates = try await detector.detect(frame.capturedImage)
            guard run == generation, isRunning, !Task.isCancelled else { return }
            guard ProcessInfo.processInfo.systemUptime - frame.timestamp <= ObjectDetectionState.retentionInterval else {
                state.expire(at: ProcessInfo.processInfo.systemUptime)
                publish()
                return
            }
            state.update(candidates, timestamp: frame.timestamp,
                         imageSize: CGSize(width: CVPixelBufferGetHeight(frame.capturedImage),
                                           height: CVPixelBufferGetWidth(frame.capturedImage)))
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
        state.suspend()
        publish()
        readiness = .planned
    }

    func reset() {
        stop()
        state = ObjectDetectionState()
        publish()
    }

    func select(_ id: UUID) {
        state.expire(at: ProcessInfo.processInfo.systemUptime)
        state.select(id)
        publish()
    }

    func clearSelection() {
        state.clearSelection()
        publish()
    }

    private func fail(_ error: Error) {
        stop()
        readiness = .unavailable(reason: "Object detection is unavailable. " + error.localizedDescription)
    }

    private func publish() {
        if snapshot != state.snapshot { snapshot = state.snapshot }
    }

    deinit {
        consumer?.cancel()
        watchdog?.cancel()
    }
}
