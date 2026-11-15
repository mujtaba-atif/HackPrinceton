import SwiftUI

struct LocateScreen: View {
    var onBack: () -> Void = {}
    /// Listens for "go back", and for the object's name until one is given. The conversational agent
    /// is deliberately not on this screen *while it is being guided*: steering a hand is a stream of
    /// short, exact directions driven by what the camera sees frame by frame, which is
    /// `DistanceBeepController` reading out its own state — there is nothing there for a language model
    /// to decide, and having one meant it held the audio session (LiveKit runs the hardware in its own
    /// mode), which cost this screen its tone.
    ///
    /// Once the three steps are done the tone has nothing left to say, and `ObjectConversation` hands
    /// the screen over to the agent — which is when this listener stops and the agent's own keywords
    /// become the way back.
    @StateObject private var listener = VoiceListener()
    /// The one AR session; every detector here reads its frames through the broker.
    @StateObject private var camera = IrisCameraController()
    // ObjectDetector runs Vision hand pose plus LiDAR distances (YOLO EGOHOS is disabled).
    @StateObject private var detector = ObjectDetector()
    @State private var listenTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?
    @State private var frameTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private let backKeywords = ["go back", "back", "return", "previous", "exit", "leave", "quit", "cancel"]
    /// What this screen guides to: a class of the segmentation model, named by the user. Anything the
    /// model doesn't know falls back to bottles.
    private static let defaultTarget = "bottle"
    @State private var target = LocateScreen.defaultTarget
    private let question = "What do you want to find?"
    /// Guidance must not depend on someone having spoken: after this long with no answer, it starts
    /// with the default target.
    private let namingGrace: TimeInterval = 12
    /// Guidance owns the screen's audio from the moment it starts, and it starts exactly once.
    @State private var guidanceStarted = false
    @StateObject private var segmenter = SegmentationDetector()
    @StateObject private var beepController = DistanceBeepController()
    /// What happens after the third step: the label is read off the object the user is now holding and
    /// handed to the agent, which says what it is and then answers questions about it. It ignores every
    /// frame until then, so none of the above changes.
    @StateObject private var conversation = ObjectConversation()

    var body: some View {
        // Full-screen geometry so the overlay covers the same area as the camera preview.
        GeometryReader { geo in
            ZStack {
                MainArt.background.color
                    .ignoresSafeArea()

                ARCameraPreview(session: camera.session)
                    .ignoresSafeArea()

                // Over the camera feed but under the detection overlay: it's a hint at the edges of
                // the screen, not something to read through.
                GuidanceRipple(cue: beepController.cue)
                    .ignoresSafeArea()

                SegmentationOverlay(
                    segments: segmenter.segments,
                    maskImage: segmenter.maskImage,
                    imageSize: segmenter.uprightImageSize,
                    viewSize: geo.size
                ) { contentSize in
                    BoundingBoxOverlay(
                        detections: detector.detections,
                        handPoint: detector.handPoint,
                        leftHandJointPoints: detector.leftHandJointPoints,
                        rightHandJointPoints: detector.rightHandJointPoints,
                        leftHandHoldingObject: detector.leftHandHoldingObject,
                        rightHandHoldingObject: detector.rightHandHoldingObject,
                        viewSize: contentSize,
                        selectedPoint: detector.selectedPoint,
                        leftHandCenter: detector.leftHandCenter,
                        rightHandCenter: detector.rightHandCenter,
                        leftHandEdge: detector.leftHandEdge,
                        rightHandEdge: detector.rightHandEdge,
                        objectFound: detector.objectFound,
                        approaching: detector.approaching,
                        objectCenter: detector.objectCenter,
                        cameraDistance: detector.cameraDistance,
                        objectClose: detector.objectClose
                    )
                }
                // Both detectors keep running through the conversation — the pipeline is untouched —
                // but their masks, boxes and fingertip distances are the guidance's working out, and
                // the guidance is over. `.opacity` rather than a branch, so it fades rather than cuts.
                .opacity(conversation.stage == .idle ? 1 : 0)

                // Over everything, because from the handoff on it *is* the screen.
                ConversationWater(mood: conversation.mood)
                    .ignoresSafeArea()
            }
            .onAppear {
                conversation.onBack = { onBack() }
                // The agent is about to take the audio hardware, so both of the things holding it let
                // go first: the recogniser's microphone and the guidance tone's engine.
                conversation.onHandOff = {
                    listenTask?.cancel()
                    listener.stop()
                    beepController.shutdown()
                }
                // No agent to talk to. It says what it can off the label itself, and the screen takes
                // its own listener back so "go back" still works.
                conversation.onEnded = {
                    Task {
                        await Speaker.shared.waitUntilIdle()
                        listenForBack()
                    }
                }
                // `session.run` is heavy and the navigation push is still animating; starting it on top
                // of the push is what made the way in here stutter.
                startTask = Task {
                    try? await Task.sleep(for: .seconds(0.3))
                    guard !Task.isCancelled else { return }
                    await camera.start()
                }
            }
            .onChange(of: camera.state) { _, state in
                if state == .running { startFrames() } else { stopFrames() }
            }
            .onReceive(segmenter.$objectMask) { detector.objectMask = $0 }
            .onReceive(
                detector.$leftHandEdge
                    .combineLatest(detector.$rightHandEdge, detector.$objectFound)
                    .combineLatest(detector.$approaching, detector.$objectClose)
            ) { measurements, approaching, objectClose in
                let (leftEdge, rightEdge, objectFound) = measurements
                beepController.update(
                    leftEdge: leftEdge,
                    rightEdge: rightEdge,
                    objectFound: objectFound,
                    approaching: approaching,
                    objectClose: objectClose,
                    objectCenter: segmenter.objectMask?.center
                )
            }
            // The last step is done: the object is in the user's hand and held close enough to read, so
            // the screen changes hands. `begin` latches, which matters here — `.ready` can fall back to
            // `.contact` and return if the object dips out of the frame, and that must not start a
            // second conversation.
            .onChange(of: beepController.phase) { _, phase in
                guard phase == .ready else { return }
                conversation.begin(objectName: target)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await camera.resumeAfterAppLifecyclePause() }
                } else {
                    camera.pauseForAppLifecycle()
                }
            }
            .onDisappear {
                conversation.stop()
                beepController.shutdown()
                startTask?.cancel()
                stopFrames()
                camera.stop()
            }
            // Haptic tap when the hand reaches the object (`approaching` latches the first found, so grip
            // flicker while bringing it closer doesn't re-fire), and again once it's close enough to read.
            .sensoryFeedback(.success, trigger: detector.approaching) { _, active in active }
            .sensoryFeedback(.success, trigger: detector.objectClose) { _, close in close }
            .task {
                await askForTarget()
            }
            .onDisappear {
                listenTask?.cancel()
                listener.stop()
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { statusBlob }
        .animation(.easeInOut, value: beepController.phase)
        .animation(.easeInOut, value: guidanceStarted)
        .animation(.easeInOut, value: conversation.stage)
        .animation(.easeInOut, value: conversation.agentStatus)
    }

    /// Whoever has the screen, in writing, in the one blob of water at the bottom of it. For the three
    /// steps that is the distance the camera is measuring with the step under it — the step the voice
    /// announces and the chime marks, so a demo can be followed by someone who isn't wearing the
    /// headphones — and after the handoff the conversation's own state, which has nothing to measure.
    @ViewBuilder
    private var statusBlob: some View {
        switch conversation.stage {
        case .idle:
            if guidanceStarted {
                StatusBlob(
                    measurement: guidanceDistance.map { ObjectDetector.inches($0) },
                    goal: guidanceGoal,
                    text: guidanceLabel,
                    systemImage: guidanceIcon,
                    highlighted: detector.approaching ? detector.objectClose : detector.objectFound
                )
            } else if listener.isListening {
                ListeningIndicator()
            }
        case .reading:
            StatusBlob(text: "Reading the label…", systemImage: "text.viewfinder")
        case .talking:
            StatusBlob(status: conversation.agentStatus)
        case .ended:
            StatusBlob(text: "Say go back to finish", systemImage: "mic.fill")
        }
    }

    /// What the blob puts on its big line: how far the hand still has to travel, or — once the object
    /// has been picked up — how far it is from the camera. `nil` while nothing is being measured, so the
    /// blob is the step alone rather than a readout of "—".
    private var guidanceDistance: Float? {
        if detector.approaching { return detector.cameraDistance }
        if detector.selectedPoint != nil {
            return [detector.leftHandToPointDistance, detector.rightHandToPointDistance].compactMap { $0 }.min()
        }
        if detector.leftHandEdge != nil || detector.rightHandEdge != nil {
            return [detector.leftHandEdge?.distance, detector.rightHandEdge?.distance].compactMap { $0 }.min()
        }
        return [detector.leftHandDistance, detector.rightHandDistance].compactMap { $0 }.min()
    }

    /// Where that distance has to get to, on the step that has one: the object is in the hand and being
    /// brought up to the camera, and "closer" means closer to a number.
    private var guidanceGoal: String? {
        guard detector.approaching, !detector.objectClose else { return nil }
        return "→ " + String(format: "%.0f in", ObjectDetector.readDistance * 39.3701)
    }

    /// The step, in the words the voice used to announce it — `Phase` owns both so they can't drift.
    /// The one thing said here that isn't a step is being too close for the camera to focus, which is
    /// checked first: it is why the read isn't happening, even while still debounced as close enough.
    private var guidanceLabel: String {
        tooClose ? "Too close · Move it back" : beepController.phase.label
    }

    private var guidanceIcon: String {
        tooClose ? "exclamationmark.circle.fill" : beepController.phase.icon
    }

    private var tooClose: Bool {
        guard detector.approaching, let distance = detector.cameraDistance else { return false }
        return distance < ObjectDetector.tooCloseDistance
    }

    /// Iris asks what to find, then points segmentation at that class. A name the model doesn't know
    /// (or silence for `namingGrace`) keeps the default target.
    private func askForTarget() async {
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, !guidanceStarted else { return }
        Speaker.shared.speak(question)
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, !guidanceStarted else { return }

        let grace = Task {
            try? await Task.sleep(for: .seconds(namingGrace))
            guard !Task.isCancelled, !guidanceStarted else { return }
            listener.stop()
            beginGuidance()
        }
        await listener.start(
            commands: ["back": backKeywords],
            onCommand: { _ in
                grace.cancel()
                onBack()
            },
            onUtterance: { heard in
                grace.cancel()
                let spoken = TargetParser.extract(from: heard)
                if let match = AssistantFacts.matchClass(spoken, in: segmenter.availableClasses) {
                    target = match
                } else if !spoken.isEmpty {
                    Speaker.shared.speak("I can't look for \(spoken) yet, so I'll look for a \(Self.defaultTarget).")
                }
                beginGuidance()
            }
        )
    }

    /// Hands the screen to `DistanceBeepController` for good — it owns the voice and the tone from
    /// here — and leaves the recogniser listening for one word.
    private func beginGuidance() {
        guard !guidanceStarted else { return }
        guidanceStarted = true
        let className = target
        segmenter.classFilter = { $0 == className }
        print("Locate: guiding to \(target)")
        beepController.setTarget(target)
        // `begin`'s greeting is the handover line, and it is held back behind anything still being said
        // (`pendingGreeting`, gated on `Speaker.isBusy`), so it can't land on top of the question.
        beepController.begin()
        listenForBack()
    }

    /// The screen's own way out, for as long as the agent doesn't have the microphone. Started here,
    /// stopped at the handoff (`conversation.onHandOff`), and started again if the agent turns out not
    /// to be there at all.
    private func listenForBack() {
        listenTask?.cancel()
        listenTask = Task { await listener.start(commands: ["back": backKeywords]) { _ in onBack() } }
    }

    /// Every frame goes to both detectors and the conversation; each throttles itself.
    private func startFrames() {
        let frames = camera.makeFrameStream()
        frameTask?.cancel()
        frameTask = Task {
            for await frame in frames {
                guard !Task.isCancelled else { return }
                detector.process(frame: frame)
                segmenter.process(frame: frame)
                // Dropped until the guidance is over and the label is being read — see
                // `ObjectConversation.process`.
                conversation.process(frame: frame)
            }
        }
    }

    private func stopFrames() {
        frameTask?.cancel()
        frameTask = nil
    }
}

#Preview {
    LocateScreen()
}
