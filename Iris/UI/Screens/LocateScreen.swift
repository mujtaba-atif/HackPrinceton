import SwiftUI

struct LocateScreen: View {
    var onBack: () -> Void = {}

    /// Listens for "go back", and for the object's name until one is given. The conversational agent
    /// is deliberately not on this screen *while it is guiding*: steering a hand is a stream of short,
    /// exact directions driven by what the camera sees frame by frame. Once the three steps are done,
    /// `ObjectConversation` hands the screen to the agent, whose own keywords become the way back.
    @StateObject private var listener = VoiceListener()
    @StateObject private var camera = IrisCameraController()
    @StateObject private var detection = ObjectDetectionService()
    @StateObject private var hands = HandTrackingService()
    @StateObject private var tracker = LocateTracker()
    @StateObject private var beepController = DistanceBeepController()
    @StateObject private var conversation = ObjectConversation()
    @Environment(\.scenePhase) private var scenePhase

    @State private var listenTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?
    @State private var frameTask: Task<Void, Never>?
    @State private var guidanceStarted = false
    /// What this screen guides to, once named.
    @State private var target: String?

    private let backKeywords = ["go back", "back", "return", "previous", "exit", "leave", "quit", "cancel"]
    private let question = "What would you like me to locate?"
    /// Guidance never waits on speech: a screen that stays quiet until someone answers is the
    /// problem this feature exists to solve. After this long with no name, Iris guides to the most
    /// prominent object it can see.
    private let namingGrace: TimeInterval = 12
    /// Measurements run at about 10 Hz.
    private let measureInterval: TimeInterval = 0.1

    var body: some View {
        ZStack {
            MainArt.background.color
                .ignoresSafeArea()
            ARCameraPreview(session: camera.session)
                .ignoresSafeArea()
            // Over the camera feed but under the detection overlay: a hint at the screen's edges.
            GuidanceRipple(cue: beepController.cue)
                .ignoresSafeArea()
            ZStack {
                ObjectDetectionOverlay(snapshot: targetOnly, select: detection.select)
                HandTrackingOverlay(snapshot: hands.snapshot)
            }
            .ignoresSafeArea()
            .allowsHitTesting(conversation.stage == .idle)
            // The boxes and joints are the guidance's working out; once it is over they fade.
            .opacity(conversation.stage == .idle ? 1 : 0)
            // Over everything, because from the handoff on it *is* the screen.
            ConversationWater(mood: conversation.mood)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { statusBlob }
        .navigationBarBackButtonHidden(true)
        .animation(.easeInOut, value: beepController.phase)
        .animation(.easeInOut, value: guidanceStarted)
        .animation(.easeInOut, value: conversation.stage)
        .animation(.easeInOut, value: conversation.agentStatus)
        .sensoryFeedback(.success, trigger: tracker.approaching) { _, active in active }
        .sensoryFeedback(.success, trigger: tracker.objectClose) { _, close in close }
        .onAppear(perform: setUp)
        .task { await askForTarget() }
        .onChange(of: camera.state) { _, state in
            if state == .running { startPipelines() } else { stopPipelines() }
        }
        .onChange(of: beepController.phase) { _, phase in
            // The last step is done: the object is in the user's hand and close enough to read.
            // `begin` latches, so `.ready` falling back to `.contact` can't start a second conversation.
            guard phase == .ready else { return }
            conversation.begin(objectName: target ?? "object")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.resumeAfterAppLifecyclePause() }
            } else {
                listener.stop()
                camera.pauseForAppLifecycle()
            }
        }
        .onDisappear(perform: tearDown)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBlob: some View {
        switch conversation.stage {
        case .idle:
            if guidanceStarted {
                StatusBlob(
                    measurement: guidanceDistance.map { LocateTracker.inches($0) },
                    goal: guidanceGoal,
                    text: guidanceLabel,
                    systemImage: guidanceIcon,
                    highlighted: tracker.approaching ? tracker.objectClose : tracker.objectFound
                )
            } else {
                ListeningIndicator(text: listener.isListening ? "Listening…" : "Getting ready…",
                                   systemImage: listener.isListening ? "mic.fill" : "viewfinder")
            }
        case .reading:
            StatusBlob(text: "Reading the label…", systemImage: "text.viewfinder")
        case .talking:
            StatusBlob(status: conversation.agentStatus)
        case .ended:
            StatusBlob(text: "Say go back to finish", systemImage: "mic.fill")
        }
    }

    private var guidanceDistance: Float? {
        if tracker.approaching { return tracker.cameraDistance }
        return [tracker.leftHandEdge?.distance, tracker.rightHandEdge?.distance].compactMap { $0 }.min()
    }

    private var guidanceGoal: String? {
        guard tracker.approaching, !tracker.objectClose else { return nil }
        return "→ " + String(format: "%.0f in", LocateTracker.readDistance * 39.3701)
    }

    private var guidanceLabel: String {
        tooClose ? "Too close · Move it back" : beepController.phase.label
    }

    private var guidanceIcon: String {
        tooClose ? "exclamationmark.circle.fill" : beepController.phase.icon
    }

    private var tooClose: Bool {
        guard tracker.approaching, let distance = tracker.cameraDistance else { return false }
        return distance < LocateTracker.tooCloseDistance
    }

    /// Only the target's box, so the screen shows what is being guided to rather than everything detected.
    private var targetOnly: DetectionSnapshot {
        var snapshot = detection.snapshot
        if let selected = snapshot.selectedTarget {
            snapshot.objects = snapshot.objects.filter { $0.id == selected.object.id }
        } else if target != nil {
            snapshot.objects = []
        }
        return snapshot
    }

    // MARK: - Flow

    private func setUp() {
        conversation.onBack = { onBack() }
        // The agent is about to take the audio hardware, so both things holding it let go first.
        conversation.onHandOff = {
            listenTask?.cancel()
            listener.stop()
            beepController.shutdown()
        }
        // No agent to talk to: it says what it can off the label itself, and "go back" still works.
        conversation.onEnded = {
            Task {
                await Speaker.shared.waitUntilIdle()
                listenForBack()
            }
        }
        // `session.run` is heavy and the navigation push is still animating.
        startTask = Task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            await camera.start()
        }
    }

    /// Asks what to find (`TargetParser`), with a grace period so guidance
    /// never depends on someone speaking. Iris detects many kinds of object, so it asks.
    private func askForTarget() async {
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, target == nil else { return }
        Speaker.shared.speak(question)
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, target == nil else { return }

        let grace = Task {
            try? await Task.sleep(for: .seconds(namingGrace))
            guard !Task.isCancelled, target == nil else { return }
            listener.stop()
            let fallback = detection.latestObjects.first?.name ?? "object"
            beginGuidance(to: fallback)
        }
        await listener.start(
            commands: ["back": backKeywords],
            onCommand: { _ in
                grace.cancel()
                onBack()
            },
            onUtterance: { heard in
                grace.cancel()
                let name = TargetParser.extract(from: heard)
                beginGuidance(to: name.isEmpty ? (detection.latestObjects.first?.name ?? "object") : name)
            }
        )
    }

    /// Hands the screen to `DistanceBeepController` for good — it owns the voice and the tone from
    /// here — and leaves the recogniser listening for one word.
    private func beginGuidance(to name: String) {
        guard !guidanceStarted else { return }
        guidanceStarted = true
        target = name
        print("Locate: guiding to \(name)")
        beepController.setTarget(name)
        beepController.begin()
        listenForBack()
    }

    /// The screen's own way out, for as long as the agent doesn't have the microphone.
    private func listenForBack() {
        listenTask?.cancel()
        listenTask = Task { await listener.start(commands: ["back": backKeywords]) { _ in onBack() } }
    }

    private func startPipelines() {
        detection.start(frames: camera.makeFrameStream())
        hands.start(frames: camera.makeFrameStream())
        let frames = camera.makeFrameStream()
        frameTask?.cancel()
        frameTask = Task {
            var lastMeasured: TimeInterval = 0
            for await frame in frames {
                guard !Task.isCancelled else { return }
                // Dropped until guidance is over and the label is being read.
                conversation.process(frame: frame)
                guard frame.timestamp - lastMeasured >= measureInterval else { continue }
                lastMeasured = frame.timestamp
                selectTargetIfNeeded()
                tracker.update(frame: frame,
                               target: detection.selectedTarget?.currentBoundingBox,
                               hands: hands.snapshot.hands)
                beepController.update(
                    leftEdge: tracker.leftHandEdge,
                    rightEdge: tracker.rightHandEdge,
                    objectFound: tracker.objectFound,
                    approaching: tracker.approaching,
                    objectClose: tracker.objectClose,
                    objectCenter: detection.selectedTarget?.currentBoundingBox.map { CGPoint(x: $0.midX, y: $0.midY) }
                )
            }
        }
    }

    /// Selects the detection matching the named target, so detection keeps one stable identity for it.
    private func selectTargetIfNeeded() {
        guard let target else { return }
        if let selected = detection.selectedTarget, selected.state == .tracking { return }
        let visible = detection.latestObjects.map(VisibleObject.init)
        if let match = AssistantFacts.match(target, in: visible) {
            detection.select(match.id)
        }
    }

    private func stopPipelines() {
        frameTask?.cancel()
        frameTask = nil
        detection.stop()
        hands.stop()
    }

    private func tearDown() {
        listenTask?.cancel()
        listener.stop()
        conversation.stop()
        beepController.shutdown()
        startTask?.cancel()
        stopPipelines()
        tracker.reset()
        hands.reset()
        detection.reset()
        camera.stop()
    }
}

#Preview {
    LocateScreen()
}
