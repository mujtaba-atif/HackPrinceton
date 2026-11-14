import Combine
import Foundation

/// Reads printed text from the existing camera stream on demand. Owns no camera.
@MainActor
final class OCRService: ObservableObject {
    /// Frames sampled per read; the best result wins, which smooths over motion blur.
    static let framesPerRead = 3
    static let frameSpacing: TimeInterval = 0.25
    /// Gives up if the stream stops delivering frames (camera paused or stopped).
    static let timeout: Duration = .seconds(4)

    @Published private(set) var state: OCRState = .idle

    var latestResult: OCRResult? { state.result }

    private let recognizer = TextRecognizer()
    private var readTask: Task<OCRState, Never>?
    private var timedOut = false

    /// Reads the selected object (when it is currently tracked) or else the center of the view.
    @discardableResult
    func read(frames: AsyncStream<CameraFrame>, focus: SelectedObjectTarget?) async -> OCRState {
        readTask?.cancel()
        state = .reading
        let region = OCRGeometry.focusRegion(for: focus?.currentBoundingBox)
        let focusName = focus?.currentBoundingBox == nil ? nil : focus?.object.name
        let recognizer = recognizer
        timedOut = false

        let task = Task<OCRState, Never> {
            var best: OCRResult?
            var sampled = 0
            var lastTimestamp: TimeInterval?
            do {
                for await frame in frames {
                    if Task.isCancelled { break }
                    if let lastTimestamp, frame.timestamp - lastTimestamp < Self.frameSpacing { continue }
                    lastTimestamp = frame.timestamp
                    sampled += 1
                    let lines = try await recognizer.recognize(frame.capturedImage, region: region)
                    let result = OCRResult(lines: lines, focusName: focusName, timestamp: frame.timestamp)
                    if !lines.isEmpty, result.score > (best?.score ?? 0) { best = result }
                    if sampled >= Self.framesPerRead { break }
                }
            } catch {
                return .failed(message: "Text recognition failed. " + error.localizedDescription)
            }
            if Task.isCancelled, !self.timedOut { return .idle }
            if sampled == 0 {
                return .failed(message: "The camera isn't providing images. Start the camera and try again.")
            }
            guard let best else {
                return .noText(hint: "No readable text found. Hold the label 20 to 40 centimeters from the camera, keep it steady, and make sure it's well lit.")
            }
            return .result(best)
        }
        readTask = task
        let watchdog = Task { [weak self] in
            try await Task.sleep(for: Self.timeout)
            self?.timedOut = true
            task.cancel()
        }
        let outcome = await task.value
        watchdog.cancel()
        // A newer read may have replaced this one while it ran.
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

    func clear() {
        cancel()
        state = .idle
    }
}
