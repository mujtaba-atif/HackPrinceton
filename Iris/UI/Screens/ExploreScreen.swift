import SwiftUI

struct ExploreScreen: View {
    var onBack: () -> Void = {}

    @StateObject private var listener = VoiceListener()
    @StateObject private var camera = IrisCameraController()
    @StateObject private var guidance = LabelGuidanceService(
        configuration: ExploreScreen.guidanceConfiguration
    )
    /// Reads again when the agent (or the user) asks for a rescan mid-conversation.
    @StateObject private var rescanReader = LabelTextReader(scanInterval: 0.25)
    @StateObject private var agent = AgentSession()
    @Environment(\.scenePhase) private var scenePhase

    @State private var summaryStarted = false
    @State private var listening = false
    @State private var rescanning = false
    @State private var frameTask: Task<Void, Never>?
    @State private var listenLoop: Task<Void, Never>?

    private let backKeywords = ["go back", "back", "return", "previous", "exit", "leave", "quit", "cancel"]
    private let retryKeywords = ["again", "try again", "retry", "scan again", "read again", "one more time"]
    // A rescan is quicker than the first scan, because the agent is waiting for the result and gives up on a
    // slow tool. It reports what it has after the timeout even if it found nothing.
    private let rescanHold: TimeInterval = 1.5
    private let rescanTimeout: TimeInterval = 8

    private static var guidanceConfiguration: LabelGuidanceService.Configuration {
        var configuration = LabelGuidanceService.Configuration()
        configuration.speaksResult = AssistantConfiguration.elevenLabsAgentID == nil
        return configuration
    }

    var body: some View {
        GeometryReader { geo in
            ARCameraPreview(session: camera.session)
                .overlay {
                    ScanAreaOutline(
                        imageSize: rescanReader.uprightImageSize,
                        viewSize: geo.size,
                        foundText: guidance.readiness.characterCount > 0 || !rescanReader.lines.isEmpty,
                        progress: ringProgress
                    )
                }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { statusPill }
        .animation(.easeInOut, value: agent.status)
        .animation(.easeInOut, value: guidance.state)
        .animation(.easeInOut, value: summaryStarted)
        .sensoryFeedback(.success, trigger: summaryStarted) { _, started in started }
        .sensoryFeedback(.impact(weight: .light), trigger: agent.status) { old, new in new == .listening && old != .listening }
        .onAppear {
            agent.onEndRequested = { onBack() }
            agent.onRescan = { await performRescan() }
            agent.onEnded = { agentWentAway() }
            Task { await camera.start() }
        }
        .onChange(of: camera.state) { _, state in
            if state == .running { startReading() } else { stopReading() }
        }
        .onChange(of: guidance.state) { _, state in
            if state == .result, let reading = guidance.reading { beginSummary(with: reading) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.resumeAfterAppLifecyclePause() }
            } else {
                stopListening()
                camera.pauseForAppLifecycle()
            }
        }
        .onDisappear {
            listenLoop?.cancel()
            stopListening()
            agent.stop()
            guidance.stop()
            stopReading()
            camera.stop()
        }
    }

    // MARK: - Status

    private var ringProgress: CGFloat {
        switch guidance.state {
        case .capturing, .interpreting, .result: 1
        case .guiding: CGFloat(guidance.readiness.score)
        case .idle, .failed: 0
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if !rescanning, agent.isRunning {
            ListeningIndicator(status: agent.status)
        } else if rescanning {
            ListeningIndicator(text: "Reading again…", systemImage: "text.viewfinder")
        } else if summaryStarted {
            ListeningIndicator(text: "Text detected", systemImage: "checkmark.circle.fill")
        } else {
            switch guidance.state {
            case let .guiding(decision):
                ListeningIndicator(text: Self.label(for: decision), systemImage: Self.icon(for: decision))
            case .capturing, .interpreting:
                ListeningIndicator(text: "Hold steady…", systemImage: "timer")
            case .failed:
                ListeningIndicator(text: "Say try again, or go back", systemImage: "arrow.clockwise")
            case .idle, .result:
                ListeningIndicator(text: "Looking for text…", systemImage: "text.viewfinder")
            }
        }
    }

    private static func label(for decision: LabelGuidanceDecision) -> String {
        switch decision {
        case .searching: "Looking for text…"
        case .turnLeft: "Turn it left"
        case .turnRight: "Turn it right"
        case .moveCloser: "Move it closer"
        case .needsLight: "Too dark · Find light"
        case .holdSteady: "Hold it steady"
        case .ready: "Hold still…"
        }
    }

    private static func icon(for decision: LabelGuidanceDecision) -> String {
        switch decision {
        case .searching: "text.viewfinder"
        case .turnLeft: "arrow.counterclockwise"
        case .turnRight: "arrow.clockwise"
        case .moveCloser: "plus.magnifyingglass"
        case .needsLight: "lightbulb.fill"
        case .holdSteady, .ready: "hand.raised.fill"
        }
    }

    // MARK: - Flow

    private func startReading() {
        // Whatever pushed this screen is still talking ("Explore selected"); Turn to Read's opening line
        // queues behind it.
        Task {
            await Speaker.shared.waitUntilIdle()
            guard camera.state == .running, !summaryStarted else { return }
            guidance.start(frames: camera.makeFrameStream(), target: { nil })
        }
        let frames = camera.makeFrameStream()
        frameTask?.cancel()
        frameTask = Task {
            for await frame in frames {
                guard !Task.isCancelled else { return }
                if rescanning { rescanReader.process(frame: frame) }
            }
        }
        startListenLoop()
    }

    private func stopReading() {
        frameTask?.cancel()
        frameTask = nil
        guidance.stop()
    }

    /// The microphone opens whenever nothing is coming out of the speaker, and never before: the
    /// spoken lines would otherwise be heard as commands. Not once the agent has the microphone.
    private func startListenLoop() {
        listenLoop?.cancel()
        listenLoop = Task {
            while !Task.isCancelled {
                if !listening, !summaryStarted || agentEnded, !Speaker.shared.isBusy {
                    await startListening()
                } else if listening, Speaker.shared.isBusy {
                    stopListening()
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    @State private var agentEnded = false

    private func startListening() async {
        guard !listening else { return }
        listening = true
        await listener.start(commands: ["back": backKeywords, "again": retryKeywords]) { command in
            listening = false
            switch command {
            case "again": retry()
            default: onBack()
            }
        }
        if Task.isCancelled { stopListening() }
    }

    private func stopListening() {
        listening = false
        listener.stop()
    }

    private func retry() {
        guard camera.state == .running else { return }
        summaryStarted = false
        agentEnded = false
        agent.stop()
        guidance.start(frames: camera.makeFrameStream(), target: { nil })
    }

    // The agent takes over the microphone, so our own listener stops first.
    private func beginSummary(with reading: LabelReading) {
        guard !summaryStarted else { return }
        summaryStarted = true
        stopListening()
        guard AssistantConfiguration.elevenLabsAgentID != nil, reading.hasAnyText else {
            // No agent (or nothing read): Turn to Read has already said what it could.
            agentEnded = true
            return
        }
        Speaker.shared.speak("Text detected.")
        agent.start(initialMessage: Self.summaryRequest(for: reading), prompt: Self.persona)
    }

    /// The agent never connected or dropped: say what Turn to Read made of the label instead.
    private func agentWentAway() {
        guard summaryStarted, !agentEnded else { return }
        agentEnded = true
        guidance.readSummary()
    }

    // The agent asked for another scan: clear what was read, read again, and return the new text.
    private func performRescan() async -> [String] {
        rescanning = true
        rescanReader.reset()
        let began = Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(began)
            if !rescanReader.lines.isEmpty, elapsed >= rescanHold { break }
            if elapsed >= rescanTimeout { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        rescanning = false
        return rescanReader.lines
    }

    static func summaryRequest(for reading: LabelReading) -> String {
        let text = reading.allLines.map { "- \($0)" }.joined(separator: "\n")
        var facts: [String] = []
        if let title = reading.title { facts.append("Name: \(title)\(reading.titleIsUncertain ? " (uncertain)" : "")") }
        if let strength = reading.strength { facts.append("Strength: \(strength)") }
        if let directions = reading.directions { facts.append("Directions: \(directions)") }
        if let date = reading.discardOrExpiration { facts.append("Discard or expiration: \(date)") }
        if !reading.warnings.isEmpty { facts.append("Warnings: " + reading.warnings.joined(separator: "; ")) }
        let factLines = facts.isEmpty ? "" : "\nFields matched in that text:\n" + facts.map { "- \($0)" }.joined(separator: "\n") + "\n"
        return """
        Scanned label text, in reading order (may contain misread characters):
        \(text)
        \(factLines)
        Summarize this item in one or two short sentences, then wait.
        """
    }

    /// Iris sends its own persona so the safety rule
    /// always applies (the agent retries without it if overrides aren't allowed).
    static let persona = """
    You are Iris, a voice guide for someone who cannot see. They are holding an item up to their phone's \
    camera, and you are given the text read off its label. Tell them what it is and the one or two \
    things on it that actually matter — the brand, a flavour or a strength, a warning, a date — then \
    stop and let them ask. Answer in at most three short spoken sentences, plainly, with no lists and \
    no markdown, and never read the whole label out unless they ask you to. Never mention text, \
    scanning, OCR or the camera: just say what the thing is. If what you were given is garbled or \
    empty, say so and offer to look again — `rescan` is a tool you can call for that, and it takes a \
    few seconds. Never say an item is safe to eat, drink, take or use; for food, medicine, doses, \
    allergens or dates, say what the label says and suggest checking with a pharmacist, doctor or \
    someone they trust.
    """
}

/// Outlines the part of the picture that is being read, and fills during the read. The camera image fills
/// the screen and is cropped to fit, so the outline is computed the same way.
private struct ScanAreaOutline: View {
    let imageSize: CGSize
    let viewSize: CGSize
    let foundText: Bool
    let progress: CGFloat

    private var rect: CGRect {
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let content = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let region = LabelTextReader.region
        return CGRect(
            x: region.minX * content.width - (content.width - viewSize.width) / 2,
            y: (1 - region.maxY) * content.height - (content.height - viewSize.height) / 2,
            width: region.width * content.width,
            height: region.height * content.height
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(foundText ? Color.green.opacity(0.4) : Color.white.opacity(0.8), lineWidth: 3)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeInOut, value: foundText)
            .animation(.easeInOut, value: progress)
            .allowsHitTesting(false)
    }
}

#Preview {
    ExploreScreen()
}
