import Combine
import Foundation
import UIKit

/// The one object a screen needs to add Iris's voice assistant.
///
/// Iris always uses the ElevenLabs agent when it can: the mic button starts or ends a live
/// conversation, and the agent answers from real detections and label text. Only when the agent
/// isn't configured, can't be reached, or drops does Iris fall back to basic on-device commands
/// for that turn; the next tap tries ElevenLabs again.
///
/// It reuses the screen's camera through a frame-stream closure and never creates a camera session.
@MainActor
final class VoiceAssistantCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case connecting
    }

    static let fallbackNotice = "Iris is offline right now, using basic commands."
    /// How often the scene summary is checked and, when it changed, sent to the agent.
    static let contextInterval: Duration = .seconds(2)

    @Published private(set) var transcript = ""
    @Published private(set) var response = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var canOpenSettings = false
    @Published private(set) var isBusy = false
    /// True while a turn is being handled by the on-device fallback.
    @Published private(set) var isUsingFallback = false

    let speech: SpeechOutputService
    let listener: VoiceCommandService
    let ocr: LabelSnapshotReader
    let agent: ElevenLabsAgentSession

    private let agentID: String?
    private var frameSource: (() -> AsyncStream<CameraFrame>)?
    private var detectionSource: (() -> DetectionSnapshot)?
    private var selectObject: ((UUID) -> Void)?
    private var cameraRunning: (() -> Bool)?
    private var subscriptions: Set<AnyCancellable> = []
    private var turnTask: Task<Void, Never>?
    private var contextTask: Task<Void, Never>?

    init(agentID: String? = AssistantConfiguration.elevenLabsAgentID,
         speech: SpeechOutputService? = nil,
         listener: VoiceCommandService? = nil,
         ocr: LabelSnapshotReader? = nil,
         agent: ElevenLabsAgentSession? = nil) {
        self.agentID = agentID
        self.speech = speech ?? SpeechOutputService()
        self.listener = listener ?? VoiceCommandService()
        self.ocr = ocr ?? LabelSnapshotReader()
        self.agent = agent ?? ElevenLabsAgentSession()

        // Re-publish child state so a single @ObservedObject drives the whole panel.
        for publisher in [self.speech.objectWillChange.eraseToAnyPublisher(),
                          self.listener.objectWillChange.eraseToAnyPublisher(),
                          self.ocr.objectWillChange.eraseToAnyPublisher(),
                          self.agent.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }

        self.agent.toolHandler = { [weak self] name, parameters in
            guard let self else { return .init(text: "Iris is closing.", isError: true) }
            return await self.runTool(name, parameters: parameters)
        }
        self.agent.onEnded = { [weak self] message in
            guard let self else { return }
            self.contextTask?.cancel()
            self.errorMessage = message
            self.announce(message ?? "Conversation ended")
        }
    }

    /// Connects the assistant to a screen's existing services. Call once, e.g. in `onAppear`.
    func attach(frames: @escaping () -> AsyncStream<CameraFrame>,
                detection: @escaping () -> DetectionSnapshot,
                select: @escaping (UUID) -> Void,
                isCameraRunning: @escaping () -> Bool) {
        frameSource = frames
        detectionSource = detection
        selectObject = select
        cameraRunning = isCameraRunning
    }

    // MARK: - State for the UI

    var isAgentConfigured: Bool { agentID != nil }
    var isConversationActive: Bool { agent.isActive }

    var phase: Phase {
        switch agent.state {
        case .connecting: return .connecting
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .idle, .failed: break
        }
        if listener.state.isListening { return .listening }
        if isBusy || ocr.state == .reading { return .thinking }
        if speech.isSpeaking { return .speaking }
        return .idle
    }

    var liveTranscript: String {
        if case let .listening(partial) = listener.state, !partial.isEmpty { return partial }
        if isConversationActive, !agent.lastUserTranscript.isEmpty { return agent.lastUserTranscript }
        return transcript
    }

    var liveResponse: String {
        if isConversationActive, !agent.lastAgentResponse.isEmpty { return agent.lastAgentResponse }
        return response
    }

    var context: AssistantContext {
        AssistantContext(isCameraRunning: cameraRunning?() ?? false,
                         snapshot: detectionSource?() ?? DetectionSnapshot(),
                         ocr: ocr.latestResult)
    }

    // MARK: - Actions

    /// The large mic button: start or end a conversation (or one fallback command).
    func micTapped() {
        clearError()
        if isConversationActive {
            endConversation()
            return
        }
        if listener.state.isListening {
            listener.stop()
            return
        }
        speech.stop()
        turnTask?.cancel()
        turnTask = Task {
            if await startConversation() { return }
            await runFallbackTurn()
        }
    }

    /// "Read Label": read the text in the app, then hand it to Iris (or speak it on device as a fallback).
    func readLabelTapped() {
        clearError()
        speech.stop()
        turnTask?.cancel()
        turnTask = Task {
            let state = await readLabelState()
            guard !Task.isCancelled else { return }
            if !isConversationActive, case .result = state {
                _ = await startConversation()
            }
            if isConversationActive {
                await agent.send(Self.describeRequest(for: state), displayedAs: "Read this label")
                return
            }
            // Only a successful read that couldn't reach Iris counts as a fallback; a "no text"
            // hint is spoken on device either way.
            if case .result = state { isUsingFallback = true }
            transcript = "Read this label"
            respond(with: AssistantFacts.describeText(state))
        }
    }

    /// Sends recognized text to the conversation, e.g. from the text view's "Ask Iris" button.
    func askAbout(_ result: OCRResult) {
        guard isConversationActive else { return }
        Task { await agent.send(Self.describeRequest(for: .result(result)), displayedAs: "Tell me about this label") }
    }

    /// "Stop Speaking": cut Iris off mid-sentence without hanging up.
    func stopSpeakingTapped() {
        speech.stop()
        if isConversationActive { Task { await agent.interrupt() } }
    }

    /// Ends the live conversation and turns off the microphone.
    func endConversation() {
        contextTask?.cancel()
        agent.stop()
        announce("Conversation ended")
    }

    /// Releases the microphone and all audio. Call when the screen disappears or the camera stops.
    func shutdown() {
        turnTask?.cancel()
        turnTask = nil
        contextTask?.cancel()
        contextTask = nil
        listener.cancel()
        speech.stop()
        agent.stop()
        ocr.cancel()
        isBusy = false
        isUsingFallback = false
    }

    // MARK: - ElevenLabs

    /// Returns true when a conversation is running.
    private func startConversation() async -> Bool {
        guard let agentID else { return false }
        isUsingFallback = false
        do {
            try await agent.start(agentID: agentID)
        } catch {
            if case let .failed(message) = agent.state { errorMessage = message }
            return false
        }
        guard agent.isActive else { return false }
        announce("Iris is listening")
        startContextUpdates()
        return true
    }

    /// Keeps the agent quietly informed about what the camera currently detects, so it can answer
    /// "what's in front of me" without waiting on a tool call.
    private func startContextUpdates() {
        contextTask?.cancel()
        contextTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isConversationActive else { return }
                await self.agent.updateContext("Scene update (not spoken by the user): "
                                               + AssistantFacts.visibleObjects(self.context))
                try? await Task.sleep(for: Self.contextInterval)
            }
        }
    }

    /// Hand-off: the app reads the label, the agent explains it.
    static func describeRequest(for state: OCRState) -> String {
        switch state {
        case let .result(result):
            let subject = result.focusName.map { "the \($0) they selected" } ?? "something in front of the camera"
            let lines = result.lines.map { "- \($0.text)" }.joined(separator: "\n")
            return """
            The user tapped Read Label on \(subject). Text read from it, in reading order (may contain \
            misread characters):
            \(lines)

            Say what it is in one or two short sentences, mentioning only what matters most, then wait.
            """
        default:
            return "The user tapped Read Label, but: \(AssistantFacts.describeText(state)) Tell them briefly and offer to try again."
        }
    }

    // MARK: - On-device fallback

    private func runFallbackTurn() async {
        isUsingFallback = true
        if isAgentConfigured {
            speech.speak(Self.fallbackNotice)
            if errorMessage == nil { errorMessage = Self.fallbackNotice }
            // Let the notice finish so the microphone doesn't hear it.
            while speech.isSpeaking, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(150)) }
        }
        guard !Task.isCancelled else { return }
        transcript = ""
        response = ""
        guard let heard = await listener.listen() else {
            switch listener.state {
            case let .unavailable(reason, settings):
                errorMessage = reason
                canOpenSettings = settings
            case let .failed(message):
                errorMessage = message
            default:
                respond(with: "I didn't hear anything. Tap the microphone and try again.")
            }
            return
        }
        transcript = heard
        guard let command = VoiceCommandParser.parse(heard) else { return }
        isBusy = true
        defer { isBusy = false }
        let answer: String
        switch command {
        case .stopSpeaking:
            speech.stop()
            return
        case .identify:
            answer = AssistantFacts.identify(context)
        case .listObjects:
            answer = AssistantFacts.visibleObjects(context)
        case let .find(name):
            answer = find(name)
        case .readText:
            answer = AssistantFacts.describeText(await readLabelState())
        case let .ask(question):
            answer = AssistantFacts.answer(question, context: context)
        }
        guard !Task.isCancelled else { return }
        respond(with: answer)
    }

    private func respond(with answer: String) {
        response = answer
        speech.speak(answer)
    }

    // MARK: - Shared capabilities (agent tools and fallback commands)

    private func readLabelState() async -> OCRState {
        guard let frameSource, cameraRunning?() == true else {
            return .failed(message: "The camera isn't running, so I can't read anything yet.")
        }
        return await ocr.read(frames: frameSource(), focus: detectionSource?().selectedTarget)
    }

    private func find(_ name: String) -> String {
        let result = AssistantFacts.find(name, in: context)
        if let match = result.match { selectObject?(match.id) }
        return result.answer
    }

    private func runTool(_ name: String, parameters: [String: Any]) async -> ElevenLabsAgentSession.ToolResult {
        switch name {
        case "get_visible_objects":
            return .init(text: AssistantFacts.visibleObjects(context))
        case "read_label":
            return .init(text: AssistantFacts.toolText(for: await readLabelState()))
        case "find_object":
            guard let target = (parameters["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !target.isEmpty else {
                return .init(text: "Missing the object name to find.", isError: true)
            }
            return .init(text: find(target))
        case "describe_selected_object":
            return .init(text: context.selected == nil
                         ? "No object is selected. " + AssistantFacts.identify(context)
                         : AssistantFacts.describeSelected(context))
        default:
            return .init(text: "Unknown tool \(name).", isError: true)
        }
    }

    // MARK: - Helpers

    private func clearError() {
        errorMessage = nil
        canOpenSettings = false
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
