import Combine
import CoreGraphics
import Foundation

/// What Iris says for each guidance event. Short, action-first phrases that work read aloud.
enum LabelGuidancePhrases {
    enum TurnDirection: Equatable { case left, right }

    static let introduction = "Hold the item up to the camera."
    static let ready = "Stop. Hold still while I read."
    static let readingNow = "Reading now. Hold still."

    static func phrase(for event: LabelGuidanceEvent, searchDirection: TurnDirection,
                       explainConvention: Bool) -> String? {
        switch event {
        case let .instruct(decision):
            switch decision {
            case .searching:
                return "Turn it slowly to the \(name(searchDirection)) until I find the label."
                    + (explainConvention ? convention(searchDirection) : "")
            case .turnLeft:
                return "Turn it left." + (explainConvention ? convention(.left) : "")
            case .turnRight:
                return "Turn it right." + (explainConvention ? convention(.right) : "")
            case .moveCloser: return "Move it closer to the camera."
            case .needsLight: return "It's too dark. Move to better light."
            case .holdSteady: return "Hold it steady."
            case .ready: return ready
            }
        case .encourage:
            return "Good, keep going."
        case .wrongWay:
            return "Other way."
        case .trySweepOtherWay:
            return "I still can't find text. Now turn it slowly to the \(name(searchDirection)), "
                + "or tilt it toward the camera."
        case .noTextFound:
            return nil
        }
    }

    static func requiresConvention(_ event: LabelGuidanceEvent) -> Bool {
        if case let .instruct(decision) = event {
            return decision == .searching || decision.isTurn
        }
        return false
    }

    private static func name(_ direction: TurnDirection) -> String {
        direction == .left ? "left" : "right"
    }

    private static func convention(_ direction: TurnDirection) -> String {
        " That means the front of it moves toward your \(name(direction))."
    }
}

/// Guides the user to turn a held item until its label faces the camera, then reads it.
///
/// Consumes the existing camera broker's frames only while active, and releases them when it finishes.
/// Reads the selected object's box from detection and an optional distance from depth sensing,
/// both through read-only closures, so it never touches their state.
@MainActor
final class LabelGuidanceService: ObservableObject {
    struct Configuration {
        /// Seconds between analyzed frames (about 5 per second).
        var analysisInterval: TimeInterval = 0.2
        var maximumFrameAge: TimeInterval = 0.5
        /// Guidance gives up after this long without a readable label.
        var guidanceTimeout: TimeInterval = 25
        /// Accurate OCR passes merged for the final read.
        var captureFrameCount = 4
        /// How long to keep reading a selected object's last position after detection loses it
        /// (a hand turning the item often hides it from the detector).
        var lostTargetGrace: TimeInterval = 3
        var maximumConsecutiveFailures = 6
    }

    @Published private(set) var state: LabelGuidanceState = .idle
    @Published private(set) var readiness: LabelReadiness = .empty
    @Published private(set) var reading: LabelReading?
    @Published private(set) var usesDetectedObject = false
    /// The last thing Iris said, shown on screen and used by Repeat.
    @Published private(set) var lastMessage = ""

    let speech: SpeechOutputService
    private let cues: LabelGuidanceCueing
    private let processor: LabelFrameProcessor
    private let interpreter: LabelInterpreting
    private let analyzer: LabelOrientationAnalyzer
    private let configuration: Configuration

    private var stabilizer = LabelGuidanceStabilizer()
    private var accumulator = LabelTextAccumulator()
    private var consumer: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var generation = UUID()
    private var targetProvider: @MainActor () -> SelectedObjectTarget? = { nil }
    private var distanceProvider: @MainActor () -> Double? = { nil }
    private var startedAt: TimeInterval = 0
    private var lastAnalysisAt: TimeInterval = -.infinity
    private var capturedFrames = 0
    private var consecutiveFailures = 0
    private var searchDirection: LabelGuidancePhrases.TurnDirection = .left
    private var hasExplainedConvention = false

    init(speech: SpeechOutputService? = nil,
         cues: LabelGuidanceCueing? = nil,
         processor: LabelFrameProcessor = LabelFrameProcessor(),
         interpreter: LabelInterpreting = OfflineLabelInterpreter(),
         analyzer: LabelOrientationAnalyzer = LabelOrientationAnalyzer(),
         configuration: Configuration = Configuration()) {
        self.speech = speech ?? SpeechOutputService()
        self.cues = cues ?? HapticLabelCuePlayer()
        self.processor = processor
        self.interpreter = interpreter
        self.analyzer = analyzer
        self.configuration = configuration
    }

    // MARK: Control

    /// - Parameters:
    ///   - frames: A fresh stream from `IrisCameraController.makeFrameStream()`.
    ///   - target: Returns the currently selected object, if any. Without one, the frame's center is read.
    ///   - distance: Returns a measured distance to the selected object in meters, if available.
    func start(frames: AsyncStream<CameraFrame>,
               target: @escaping @MainActor () -> SelectedObjectTarget?,
               distance: @escaping @MainActor () -> Double? = { nil }) {
        stop()
        let run = generation
        targetProvider = target
        distanceProvider = distance
        startedAt = ProcessInfo.processInfo.systemUptime
        state = .guiding(.searching)
        cues.prepare()
        say(LabelGuidancePhrases.introduction)

        consumer = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self, self.generation == run else { return }
                await self.handle(frame, run: run)
            }
            guard let self, self.generation == run, self.state.isActive else { return }
            self.fail(.cameraStopped)
        }
        startTicker(run: run)
    }

    /// Ends guidance or a result, silences speech, and releases the camera stream.
    func stop() {
        generation = UUID()
        consumer?.cancel()
        consumer = nil
        ticker?.cancel()
        ticker = nil
        speech.stop()
        stabilizer = LabelGuidanceStabilizer()
        accumulator.reset()
        readiness = .empty
        reading = nil
        lastMessage = ""
        capturedFrames = 0
        consecutiveFailures = 0
        lastAnalysisAt = -.infinity
        searchDirection = .left
        hasExplainedConvention = false
        usesDetectedObject = false
        state = .idle
    }

    /// Skips the remaining guidance and reads whatever is facing the camera now.
    func readNow() {
        guard case .guiding = state else { return }
        say(LabelGuidancePhrases.readingNow)
        beginCapture()
    }

    func readSummary() {
        guard let reading else { return }
        say(LabelReadingSpeech.summary(reading))
    }

    func readMoreDetails() {
        guard let reading else { return }
        say(LabelReadingSpeech.details(reading))
    }

    func readEverything() {
        guard let reading else { return }
        say(LabelReadingSpeech.everything(reading))
    }

    func repeatLast() {
        guard !lastMessage.isEmpty else { return }
        speech.speak(lastMessage)
    }

    func stopSpeaking() {
        speech.stop()
    }

    // MARK: Frames

    private func handle(_ frame: CameraFrame, run: UUID) async {
        let now = ProcessInfo.processInfo.systemUptime
        guard state == .capturing || isGuiding,
              now - frame.timestamp <= configuration.maximumFrameAge,
              now - lastAnalysisAt >= configuration.analysisInterval else { return }
        lastAnalysisAt = now

        let plan = LabelCropPlanner.plan(objectBox: objectBox(at: now))
        usesDetectedObject = plan.usesDetectedObject
        let level: TextRecognitionLevel = state == .capturing ? .accurate : .fast

        let analysis: LabelFrameAnalysis
        do {
            analysis = try await processor.analyze(frame, plan: plan, level: level)
            consecutiveFailures = 0
        } catch {
            guard generation == run else { return }
            consecutiveFailures += 1
            if consecutiveFailures >= configuration.maximumConsecutiveFailures {
                fail(.recognitionFailed(error.localizedDescription))
            }
            return
        }
        guard generation == run else { return }

        if state == .capturing {
            accumulator.add(analyzer.usableLines(analysis.lines))
            capturedFrames += 1
            if capturedFrames >= configuration.captureFrameCount {
                await finishCapture(run: run)
            }
            return
        }
        guard isGuiding else { return }

        let (frameReadiness, decision) = analyzer.analyze(analysis.lines, objectRegion: plan.objectRegion,
                                                          luminance: analysis.luminance,
                                                          distanceMeters: distanceProvider())
        readiness = frameReadiness
        // Collect text while the item turns; curved labels are read in pieces.
        accumulator.add(analyzer.usableLines(analysis.lines))

        if let event = stabilizer.update(decision: decision, readiness: frameReadiness,
                                         at: ProcessInfo.processInfo.systemUptime) {
            handle(event)
        }
        if isGuiding, let current = stabilizer.current {
            state = .guiding(current)
        }
    }

    private func objectBox(at now: TimeInterval) -> CGRect? {
        guard let target = targetProvider() else { return nil }
        if let box = target.currentBoundingBox { return box }
        // Lost target: keep reading where it was for a moment, since a turning hand often hides it.
        if now - target.lastSeenTimestamp <= configuration.lostTargetGrace { return target.object.boundingBox }
        return nil
    }

    private func handle(_ event: LabelGuidanceEvent) {
        switch event {
        case .instruct(.ready):
            say(LabelGuidancePhrases.ready)
            beginCapture()
            return
        case .noTextFound:
            fail(.noTextFound)
            return
        case .trySweepOtherWay:
            searchDirection = searchDirection == .left ? .right : .left
        default:
            break
        }

        let explain = !hasExplainedConvention && LabelGuidancePhrases.requiresConvention(event)
        guard let phrase = LabelGuidancePhrases.phrase(for: event, searchDirection: searchDirection,
                                                       explainConvention: explain) else { return }
        if explain { hasExplainedConvention = true }
        let introIsPlaying = speech.isSpeaking && lastMessage == LabelGuidancePhrases.introduction
        let priority: SpeechOutputService.Priority = event == .encourage ? .skipIfBusy
            : introIsPlaying ? .enqueue : .interrupt
        say(phrase, priority: priority)
    }

    private func beginCapture() {
        cues.success()
        capturedFrames = 0
        state = .capturing
    }

    private func finishCapture(run: UUID) async {
        state = .interpreting
        let lines = accumulator.orderedLines
        let result = await interpreter.interpret(lines)
        guard generation == run else { return }
        releaseFrames()
        reading = result
        state = .result
        say(LabelReadingSpeech.summary(result))
    }

    private func fail(_ failure: LabelGuidanceFailure) {
        releaseFrames()
        state = .failed(failure)
        cues.failure()
        say(failure.spokenMessage)
    }

    private func releaseFrames() {
        consumer?.cancel()
        consumer = nil
        ticker?.cancel()
        ticker = nil
    }

    private var isGuiding: Bool {
        if case .guiding = state { return true }
        return false
    }

    private func say(_ text: String, priority: SpeechOutputService.Priority = .interrupt) {
        lastMessage = text
        speech.speak(text, priority: priority)
    }

    // MARK: Ticks and timeout

    /// Ticks faster as more of the label is visible, and enforces the guidance timeout even if frames stop.
    private func startTicker(run: UUID) {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == run else { return }
                if self.isGuiding,
                   ProcessInfo.processInfo.systemUptime - self.startedAt > self.configuration.guidanceTimeout {
                    self.fail(.timedOut)
                    return
                }
                let score = self.readiness.score
                if self.isGuiding, !self.speech.isSpeaking {
                    self.cues.tick(readiness: score)
                }
                let interval = 0.9 - 0.65 * score
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }
}
