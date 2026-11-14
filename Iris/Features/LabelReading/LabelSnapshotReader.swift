import Combine
import Foundation

/// Reads the label in view without spoken guidance: a few accurate passes over fresh frames,
/// merged with `LabelTextAccumulator`. Built on the same crop planner and frame processor as
/// Turn to Read, and owns no camera.
@MainActor
final class LabelSnapshotReader: ObservableObject {
    static let framesPerRead = 4
    static let frameSpacing: TimeInterval = 0.2
    /// Gives up if the stream stops delivering frames (camera paused or stopped).
    static let timeout: Duration = .seconds(5)

    @Published private(set) var state: OCRState = .idle

    var latestResult: OCRResult? { state.result }

    private let processor: LabelFrameProcessor
    private var readTask: Task<OCRState, Never>?
    private var timedOut = false

    init(processor: LabelFrameProcessor = LabelFrameProcessor()) {
        self.processor = processor
    }

    /// Reads the selected object (while it is tracked) or else the center of the view.
    @discardableResult
    func read(frames: AsyncStream<CameraFrame>, focus: SelectedObjectTarget?) async -> OCRState {
        readTask?.cancel()
        state = .reading
        timedOut = false
        let box = focus?.currentBoundingBox
        let plan = LabelCropPlanner.plan(objectBox: box)
        let focusName = box == nil ? nil : focus?.object.name
        let processor = processor

        let task = Task<OCRState, Never> {
            var accumulator = LabelTextAccumulator()
            var sampled = 0
            var lastTimestamp: TimeInterval?
            var lastError: Error?
            for await frame in frames {
                if Task.isCancelled { break }
                if let lastTimestamp, frame.timestamp - lastTimestamp < Self.frameSpacing { continue }
                lastTimestamp = frame.timestamp
                sampled += 1
                do {
                    let analysis = try await processor.analyze(frame, plan: plan, level: .accurate)
                    accumulator.add(LabelOrientationAnalyzer().usableLines(analysis.lines))
                } catch {
                    lastError = error
                }
                if sampled >= Self.framesPerRead { break }
            }
            if Task.isCancelled, !self.timedOut { return .idle }
            if sampled == 0 {
                return .failed(message: "The camera isn't providing images. Start the camera and try again.")
            }
            guard !accumulator.isEmpty else {
                if let lastError, sampled == 1 {
                    return .failed(message: "Text recognition failed. " + lastError.localizedDescription)
                }
                return .noText(hint: "No readable text found. Hold the label 20 to 40 centimeters from the camera, keep it steady, and make sure it's well lit.")
            }
            return .result(OCRResult(lines: accumulator.orderedLines, focusName: focusName,
                                     timestamp: lastTimestamp ?? 0))
        }
        readTask = task
        let watchdog = Task { [weak self] in
            try await Task.sleep(for: Self.timeout)
            self?.timedOut = true
            task.cancel()
        }
        let outcome = await task.value
        watchdog.cancel()
        if readTask == task {
            state = outcome
            readTask = nil
        }
        return outcome
    }

    func cancel() {
        readTask?.cancel()
        readTask = nil
        if state == .reading { state = .idle }
    }
}
