import SwiftUI

struct ExploreScreen: View {
    var onBack: () -> Void = {}
    @StateObject private var listener = VoiceListener()
    /// The one AR session; the reader gets its frames through the broker.
    @StateObject private var camera = IrisCameraController()
    @State private var frameTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    // Four recognition events per second feed the shared OCR readiness gate.
    @StateObject private var reader = TextReader(scanInterval: 0.25)
    @StateObject private var agent = AgentSession()
    @State private var summaryStarted = false
    @State private var listening = false
    @State private var rescanning = false
    @StateObject private var segmenter = SegmentationDetector()
    @StateObject private var detector = ObjectDetector()
    @State private var outline: [CGPoint]?
    private let backKeywords = ["go back", "back", "return", "previous", "exit", "leave", "quit", "cancel"]
    // Hints when nothing readable is in view.
    private let firstHintAfter: TimeInterval = 8
    private let laterHintEvery: TimeInterval = 12
    private let maxHints = 2
    // A rescan reports the available evidence within the agent tool's response window.
    private let rescanTimeout: TimeInterval = 8

    @State private var celebrations = 0
    /// What was read for the summary, kept so it can be read out if the agent never answers.
    @State private var readLines: [String] = []
    /// The agent couldn't connect, or dropped: Iris read the label out itself and listens for "go back".
    @State private var agentEnded = false

    var body: some View {
        StageView { stage in
            IrisPalette.ink
            ARCameraPreview(session: camera.session)
            LinearGradient(stops: [.init(color: Color(rgba: 0x061B3740), location: 0),
                                   .init(color: .clear, location: 0.32),
                                   .init(color: .clear, location: 0.6),
                                   .init(color: Color(rgba: 0x061B3750), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            CameraGlass(mode: .explore)
            if let path = scanAreaPath(in: stage) {
                ObjectOutline(path: path, style: outlineStyle, scanning: !summaryStarted || rescanning)
            }
            if camera.state == .running {
                HandGuidanceOverlay(skeletons: detector.handSkeletons,
                    outlines: [detector.leftHandJointPoints, detector.rightHandJointPoints],
                    measurements: [detector.leftHandEdge, detector.rightHandEdge].compactMap { $0 },
                    imageSize: segmenter.uprightImageSize)
            }
            Sprinkles(count: 6, quiet: true, unit: stage.unit)
            Confetti(trigger: celebrations, unit: stage.unit)
            GlassBackButton(action: onBack)
            statusPill
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .onChange(of: summaryStarted) { _, started in
            if started { celebrations += 1 }
        }
        .animation(.easeInOut, value: agent.status)
        .animation(.easeInOut, value: reader.recognition)
        .animation(.easeInOut, value: summaryStarted)
        .sensoryFeedback(.success, trigger: summaryStarted) { _, started in started }
        .sensoryFeedback(.impact(weight: .light), trigger: agent.status) { old, new in new == .listening && old != .listening }
        .onAppear {
            agent.onEndRequested = { onBack() }
            agent.onRescan = { await performRescan() }
            agent.onEnded = { agentWentAway() }
            Task { await camera.start() }
        }
        .onReceive(segmenter.$objectMask) { mask in
            detector.objectMask = mask
            outline = mask.flatMap { MaskContour.outline(of: $0) }
        }
        .onChange(of: camera.state) { _, state in
            if state == .running { startFrames() } else { stopFrames() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.resumeAfterAppLifecyclePause() }
            } else {
                camera.pauseForAppLifecycle()
            }
        }
        .task {
            // Whatever pushed this screen is still talking ("Explore object selected").
            await Speaker.shared.waitUntilIdle()
            guard !Task.isCancelled else { return }
            // Recognition proceeds while the opening instruction plays.
            Speaker.shared.speak("Hold the item in front of the camera so I can read it.")
            if let lines = await scanForText(hints: true, timeout: nil) {
                beginSummary(with: lines)
            }
        }
        .onDisappear {
            stopListening()
            agent.stop()
            stopFrames()
            camera.stop()
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if agentEnded {
            ListeningIndicator(text: listening ? "Say go back to finish" : "Iris is speaking…", speaking: !listening)
        } else if !rescanning, agent.isRunning {
            ListeningIndicator(status: agent.status)
        } else if !rescanning, summaryStarted {
            ListeningIndicator(text: "Text detected", systemImage: "checkmark.circle.fill")
        } else if reader.recognition == .reading || reader.recognition == .ready {
            ListeningIndicator(text: "Reading live…")
        } else {
            ListeningIndicator(text: "Looking for text…")
        }
    }

    private var outlineStyle: ObjectOutline.Style {
        if summaryStarted, !rescanning { return .settled }
        return reader.lines.isEmpty ? .explore : .reading
    }

    /// A real segmented silhouette replaces the former rectangular reading target.
    private func scanAreaPath(in stage: Stage) -> Path? {
        guard let outline, outline.count > 2 else { return nil }
        var path = Path()
        path.addLines(outline.map { MaskContour.aspectFill($0, image: segmenter.uprightImageSize, view: stage.size) })
        path.closeSubpath()
        return path
    }

    /// Readiness comes from matching OCR results; there is no hold timer or capture action.
    private func scanForText(hints: Bool, timeout: TimeInterval?) async -> [String]? {
        let began = Date()
        var emptySince = Date()
        var hintsGiven = 0
        while !Task.isCancelled {
            if !listening, !summaryStarted, !Speaker.shared.isBusy { await startListening() }
            let now = Date()
            if reader.recognition == .ready, !reader.lines.isEmpty { return reader.lines }
            if reader.recognition != .searching || Speaker.shared.isBusy {
                emptySince = now
            } else if hints {
                let wait = hintsGiven == 0 ? firstHintAfter : laterHintEvery
                if hintsGiven < maxHints, now.timeIntervalSince(emptySince) >= wait {
                    hintsGiven += 1
                    emptySince = now
                    speakHint("I can't read any text yet. Try holding the label closer, or say go back.")
                }
            }
            if let timeout, now.timeIntervalSince(began) >= timeout { return reader.lines }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private func performRescan() async -> [String] {
        rescanning = true
        reader.reset()
        let lines = await scanForText(hints: false, timeout: rescanTimeout) ?? []
        rescanning = false
        return lines
    }

    // The hint mentions "go back", so the microphone goes off while it plays or the listener would hear
    // it. The scan loop opens it again once the queue is empty.
    private func speakHint(_ text: String) {
        stopListening()
        Speaker.shared.speak(text)
    }

    private func startListening() async {
        guard !listening else { return }
        listening = true
        await listener.start(commands: ["back": backKeywords]) { _ in onBack() }
        // The screen can go away while the session is being set up, and `onDisappear` has then already
        // stopped a listener that wasn't running yet.
        if Task.isCancelled { stopListening() }
    }

    private func stopListening() {
        listening = false
        listener.stop()
    }

    // The agent takes over the microphone, so our own listener stops first. Connecting takes a moment anyway, so
    // it starts right away instead of waiting for "Text detected." to finish.
    private func beginSummary(with lines: [String]) {
        readLines = lines
        summaryStarted = true
        stopListening()
        Speaker.shared.speak("Text detected.")
        agent.start(initialMessage: Self.summaryRequest(for: lines))
    }

    /// The agent couldn't be reached, or went away before it was done. Without this the screen would sit on
    /// "Text detected" in silence with the microphone already handed over, and someone who can't see it
    /// would be stuck: so Iris reads the label out itself and opens the microphone for "go back".
    private func agentWentAway() {
        guard summaryStarted, !agentEnded else { return }
        agentEnded = true
        Speaker.shared.speak(Self.fallbackSummary(for: readLines))
        Task {
            await Speaker.shared.waitUntilIdle()
            await startListening()
        }
    }

    /// Said in place of the agent's summary: the label itself, which is what the user wanted to know.
    static func fallbackSummary(for lines: [String]) -> String {
        guard !lines.isEmpty else { return "I can't reach the assistant, and I couldn't make out the text. Say go back to try again." }
        return "I can't reach the assistant, but here's what it says. " + lines.prefix(6).joined(separator: ". ") + "."
    }

    /// Forwards camera frames to the reader, which throttles itself.
    private func startFrames() {
        let frames = camera.makeFrameStream()
        frameTask?.cancel()
        frameTask = Task {
            for await frame in frames {
                guard !Task.isCancelled else { return }
                reader.process(frame: frame)
                segmenter.process(frame: frame)
                detector.process(frame: frame)
            }
        }
    }

    private func stopFrames() {
        frameTask?.cancel()
        frameTask = nil
    }

    static func summaryRequest(for lines: [String]) -> String {
        let text = lines.map { "- \($0)" }.joined(separator: "\n")
        return """
        Scanned label text, in reading order (may contain misread characters):
        \(text)

        Summarize this item in one or two short sentences, then wait.
        """
    }
}

#Preview {
    ExploreScreen()
}
