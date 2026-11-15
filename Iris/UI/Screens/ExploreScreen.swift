import SwiftUI

struct ExploreScreen: View {
    var onBack: () -> Void = {}
    @StateObject private var listener = VoiceListener()
    /// The one AR session; the reader gets its frames through the broker.
    @StateObject private var camera = IrisCameraController()
    @State private var frameTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    // 4 Hz rather than the default 2: the countdown can't start until the consolidator has seen a line
    // three times, and at 2 Hz that alone was a second and a half of holding still before anything moved.
    @StateObject private var reader = TextReader(scanInterval: 0.25)
    @StateObject private var agent = AgentSession()
    @State private var summaryStarted = false
    @State private var listening = false
    @State private var rescanning = false
    @State private var currentHold: TimeInterval = 2
    @State private var holdStartedAt: Date?
    @State private var secondsLeft = 0
    @State private var ringProgress: CGFloat = 0
    @State private var holdCount = 0

    private let backKeywords = ["go back", "back", "return", "previous", "exit", "leave", "quit", "cancel"]
    // Once text is found the user holds still for this long, then the agent starts with whatever was read.
    // The countdown is evidence, not ceremony: at 4 Hz two seconds is eight more scans on top of the three
    // that found the text, which is the consolidator's whole window. Five seconds bought a fuller read of
    // the small print at the cost of holding a can out at arm's length for the better part of seven.
    private let holdDuration: TimeInterval = 2
    // The countdown restarts if the text has been out of view for this long.
    private let textLostGrace: TimeInterval = 1
    // Hints when nothing readable is in view.
    private let firstHintAfter: TimeInterval = 8
    private let laterHintEvery: TimeInterval = 12
    private let maxHints = 2
    // A rescan is quicker than the first scan, because the agent is waiting for the result and gives up on a
    // slow tool. It reports what it has after the timeout even if it found nothing.
    private let rescanHold: TimeInterval = 1.5
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
            // The reading area. The hold-steady countdown fills it with light from the bottom up.
            ObjectOutline(path: scanAreaPath(in: stage), style: outlineStyle,
                          scanning: !summaryStarted || rescanning, fill: Double(ringProgress))
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
        .animation(.easeInOut, value: holdStartedAt != nil)
        .animation(.easeInOut, value: summaryStarted)
        .sensoryFeedback(.impact(weight: .light), trigger: holdCount)
        .sensoryFeedback(.success, trigger: summaryStarted) { _, started in started }
        .sensoryFeedback(.impact(weight: .light), trigger: agent.status) { old, new in new == .listening && old != .listening }
        .onAppear {
            agent.onEndRequested = { onBack() }
            agent.onRescan = { await performRescan() }
            agent.onEnded = { agentWentAway() }
            Task { await camera.start() }
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
            // The read runs *underneath* this line rather than after it. The camera is already up, and
            // anyone who is going to hold something out is holding it out while the line plays — waiting
            // it out threw those scans away and started the countdown three seconds later than it had to.
            Speaker.shared.speak("Hold the item in front of the camera so I can read it.")
            if let lines = await scanForText(hold: holdDuration, hints: true, timeout: nil) {
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
        } else if holdStartedAt != nil {
            ListeningIndicator(text: "Hold steady… \(secondsLeft)", systemImage: "timer")
        } else {
            ListeningIndicator(text: "Looking for text…", systemImage: "text.viewfinder")
        }
    }

    private var outlineStyle: ObjectOutline.Style {
        if summaryStarted, !rescanning { return .settled }
        return reader.lines.isEmpty ? .explore : .reading
    }

    /// `TextReader.region` (Vision coordinates, origin bottom left) on screen, the camera image being
    /// aspect-filled.
    private func scanAreaPath(in stage: Stage) -> Path {
        let region = TextReader.region
        let normalized = CGRect(x: region.minX, y: 1 - region.maxY, width: region.width, height: region.height)
        let rect = MaskContour.aspectFill(normalized, image: reader.uprightImageSize, view: stage.size)
        return Path(roundedRect: rect, cornerRadius: 28 * stage.unit, style: .continuous)
    }

    // Waits for text, runs the countdown once it is found, and returns what was read. With `hints`, it also nudges
    // the user if nothing readable shows up. With a `timeout`, it gives up and returns whatever there is.
    // Returns nil if the screen went away.
    private func scanForText(hold: TimeInterval, hints: Bool, timeout: TimeInterval?) async -> [String]? {
        currentHold = hold
        let began = Date()
        var lastTextSeen = Date()
        var emptySince = Date()
        var hintsGiven = 0

        while !Task.isCancelled {
            // The microphone opens as soon as nothing is coming out of the speaker, and never before:
            // the opening line and the hints below both name a `backKeywords` phrase, and the listener
            // hears the speaker. Not during a rescan — by then the agent owns the microphone.
            if !listening, !summaryStarted, !Speaker.shared.isBusy { await startListening() }

            let now = Date()
            if !reader.lines.isEmpty {
                lastTextSeen = now
                emptySince = now
            } else if Speaker.shared.isBusy {
                // Time spent listening to Iris isn't time spent failing to get a read. Without this the
                // opening line — which the scan now runs underneath — counts toward the first hint, and a
                // hint counts toward the one after it.
                emptySince = now
            }

            if let holdBegan = holdStartedAt {
                if now.timeIntervalSince(lastTextSeen) >= textLostGrace {
                    resetHold()
                } else {
                    let elapsed = now.timeIntervalSince(holdBegan)
                    secondsLeft = max(0, Int((hold - elapsed).rounded(.up)))
                    if elapsed >= hold { return reader.lines }
                }
            } else if !reader.lines.isEmpty {
                startHold(at: now)
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

    // The agent asked for another scan: clear what was read, show the countdown again, and return the new text.
    private func performRescan() async -> [String] {
        let began = Date()
        print("Rescan started")
        rescanning = true
        reader.reset()
        resetHold()
        let lines = await scanForText(hold: rescanHold, hints: false, timeout: rescanTimeout) ?? []
        resetHold()
        rescanning = false
        print("Rescan finished: \(lines.count) lines in \(String(format: "%.1f", Date().timeIntervalSince(began))) s")
        return lines
    }

    private func startHold(at date: Date) {
        holdStartedAt = date
        secondsLeft = Int(currentHold)
        holdCount += 1
        withAnimation(.linear(duration: currentHold)) { ringProgress = 1 }
    }

    private func resetHold() {
        holdStartedAt = nil
        withAnimation(.easeOut(duration: 0.2)) { ringProgress = 0 }
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
        holdStartedAt = nil
        withAnimation(.easeOut(duration: 0.3)) { ringProgress = 0 }
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
