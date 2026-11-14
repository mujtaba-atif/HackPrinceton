import Combine
import ElevenLabs
import Foundation

/// One ElevenLabs Conversational AI session. The agent hears the user, thinks, and speaks
/// with ElevenLabs; it learns about the camera only through Iris's client tools, silent context
/// updates, and messages the app sends on the user's behalf.
@MainActor
final class ElevenLabsAgentSession: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
        case failed(message: String)

        var isActive: Bool {
            switch self {
            case .listening, .thinking, .speaking, .connecting: true
            case .idle, .failed: false
            }
        }
    }

    struct ToolResult {
        let text: String
        var isError = false
    }

    /// How long to wait for the greeting before sending a queued message anyway.
    static let greetingTimeout: Duration = .seconds(6)

    @Published private(set) var state: State = .idle
    @Published private(set) var lastUserTranscript = ""
    @Published private(set) var lastAgentResponse = ""

    /// Answers a client tool call. Parameters are the decoded JSON arguments.
    var toolHandler: ((_ name: String, _ parameters: [String: Any]) async -> ToolResult)?
    /// Called when the conversation ends without the app asking (agent hung up, network dropped,
    /// or the user said a goodbye phrase). `message` is nil for a user-requested end.
    var onEnded: ((_ message: String?) -> Void)?

    private var conversation: Conversation?
    private var subscriptions: Set<AnyCancellable> = []
    private var handledToolCalls: Set<String> = []
    private var isStopping = false
    private var agentID: String?
    private var connectedWithOverrides = false
    private var retriedWithoutOverrides = false
    private var agentHasSpoken = false
    private var lastContext: String?
    private var greetingWaiters: [CheckedContinuation<Void, Never>] = []

    var isActive: Bool { state.isActive }

    /// Connects to the agent. Throws if the connection could not be established.
    func start(agentID: String) async throws {
        guard !state.isActive else { return }
        self.agentID = agentID
        isStopping = false
        retriedWithoutOverrides = false
        lastUserTranscript = ""
        lastAgentResponse = ""
        state = .connecting
        do {
            try await connect(agentID: agentID, withOverrides: true)
        } catch {
            guard !isStopping else { return }
            retriedWithoutOverrides = true
            do {
                try await connect(agentID: agentID, withOverrides: false)
            } catch {
                state = .failed(message: Self.describe(error))
                throw error
            }
        }
    }

    func stop() {
        isStopping = true
        tearDown()
        if state != .idle { state = .idle }
    }

    /// Sends a request to the agent as if the user said it, after the greeting has finished.
    func send(_ text: String, displayedAs display: String? = nil) async {
        await waitForGreeting()
        guard let conversation else { return }
        lastUserTranscript = display ?? text
        try? await conversation.sendMessage(text)
    }

    /// Silently tells the agent about the scene. Only sends when the text changed.
    func updateContext(_ text: String) async {
        guard let conversation, state.isActive, state != .connecting, text != lastContext else { return }
        lastContext = text
        try? await conversation.updateContext(text)
    }

    /// Cuts the agent off mid-sentence without ending the conversation.
    func interrupt() async {
        guard let conversation, state == .speaking || state == .thinking else { return }
        try? await conversation.interruptAgent()
    }

    // MARK: - Connection

    private func connect(agentID: String, withOverrides: Bool) async throws {
        connectedWithOverrides = withOverrides
        agentHasSpoken = false
        lastContext = nil

        var config = ConversationConfig(
            onError: { error in print("ElevenLabs error: \(error.localizedDescription)") },
            onAgentResponse: { [weak self] text, _ in
                Task { @MainActor in self?.agentSaid(text) }
            },
            onUserTranscript: { [weak self] text, _ in
                Task { @MainActor in self?.userSaid(text) }
            },
            agentStateConfiguration: AgentStateConfiguration(speakingToListeningDelay: 0.3)
        )
        if withOverrides {
            config.agentOverrides = AgentOverrides(prompt: AssistantConfiguration.agentPrompt,
                                                   firstMessage: AssistantConfiguration.firstMessage)
        }

        let started = try await ElevenLabs.startConversation(
            agentId: agentID,
            config: config,
            onDisconnect: { [weak self] reason in
                Task { @MainActor in self?.handleDisconnect(reason) }
            }
        )
        guard !isStopping else {
            await started.endConversation()
            return
        }
        conversation = started
        state = .listening

        started.$agentState
            .receive(on: RunLoop.main)
            .sink { [weak self] agentState in
                guard let self, self.conversation === started else { return }
                switch agentState {
                case .listening: self.state = .listening
                case .thinking: self.state = .thinking
                case .speaking: self.state = .speaking
                }
            }
            .store(in: &subscriptions)

        started.$pendingToolCalls
            .receive(on: RunLoop.main)
            .sink { [weak self] calls in self?.handle(calls, on: started) }
            .store(in: &subscriptions)
    }

    private func handleDisconnect(_ reason: DisconnectionReason) {
        guard !isStopping, conversation != nil else { return }
        tearDown()

        // An agent that refuses prompt overrides accepts the connection, then drops it before saying
        // anything. Retry once with the dashboard configuration instead of reporting a failure.
        if connectedWithOverrides, !agentHasSpoken, !retriedWithoutOverrides, reason != .user, let agentID {
            retriedWithoutOverrides = true
            state = .connecting
            Task {
                do {
                    try await connect(agentID: agentID, withOverrides: false)
                } catch {
                    state = .failed(message: Self.describe(error))
                    onEnded?(Self.describe(error))
                }
            }
            return
        }

        state = .idle
        let message: String? = switch reason {
        case .user: nil
        case .agent: "Iris ended the conversation."
        case .error: "Iris disconnected. Check your internet connection."
        }
        onEnded?(message)
    }

    private func tearDown() {
        subscriptions.removeAll()
        handledToolCalls.removeAll()
        releaseGreetingWaiters()
        let conversation = conversation
        self.conversation = nil
        if let conversation { Task { await conversation.endConversation() } }
    }

    // MARK: - Transcripts

    private func agentSaid(_ text: String) {
        lastAgentResponse = text
        if !agentHasSpoken {
            agentHasSpoken = true
            releaseGreetingWaiters()
        }
    }

    private func userSaid(_ text: String) {
        lastUserTranscript = text
        if AssistantConfiguration.isEndRequest(text) {
            stop()
            onEnded?(nil)
        }
    }

    // MARK: - Greeting gate

    private func waitForGreeting() async {
        guard conversation != nil || state == .connecting, !agentHasSpoken else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                await withCheckedContinuation { continuation in
                    guard let self, !self.agentHasSpoken else { return continuation.resume() }
                    self.greetingWaiters.append(continuation)
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.greetingTimeout)
            }
            await group.next()
            group.cancelAll()
            await MainActor.run { self.releaseGreetingWaiters() }
        }
    }

    private func releaseGreetingWaiters() {
        let waiters = greetingWaiters
        greetingWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    // MARK: - Client tools

    private func handle(_ calls: [ClientToolCallEvent], on conversation: Conversation) {
        for call in calls where !handledToolCalls.contains(call.toolCallId) {
            handledToolCalls.insert(call.toolCallId)
            let parameters = (try? call.getParameters()) ?? [:]
            Task { [weak self] in
                guard let self else { return }
                let result = await self.toolHandler?(call.toolName, parameters)
                    ?? ToolResult(text: "This tool isn't available.", isError: true)
                guard self.conversation === conversation else { return }
                try? await conversation.sendToolResult(for: call.toolCallId, result: result.text,
                                                       isError: result.isError)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? ConversationError {
            switch error {
            case .authenticationFailed:
                return "Iris couldn't sign in to the voice service. Check ELEVENLABS_AGENT_ID."
            case .connectionFailed, .agentTimeout:
                return "Couldn't reach Iris's voice service. Check your internet connection."
            default:
                return error.localizedDescription
            }
        }
        return "Couldn't start Iris's voice. " + error.localizedDescription
    }
}
