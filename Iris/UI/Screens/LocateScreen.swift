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
    /// The wait for the object's name. Held so leaving the screen cancels it: a stray one would start
    /// guidance (and its voice and tone) on a screen that has already gone.
    @State private var graceTask: Task<Void, Never>?
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

    /// The object's silhouette from the live segmentation mask, normalized to the upright image.
    @State private var outline: [CGPoint]?
    /// Bumped on first contact with the object, for the confetti.
    @State private var celebrations = 0

    var body: some View {
        StageView { stage in
            IrisPalette.ink
            ARCameraPreview(session: camera.session)
            // The design's shade: a little darker at the top and bottom, where the controls sit.
            LinearGradient(stops: [.init(color: Color(rgba: 0x061B3740), location: 0),
                                   .init(color: .clear, location: 0.32),
                                   .init(color: .clear, location: 0.6),
                                   .init(color: Color(rgba: 0x061B3750), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            // Shared optical rails remain continuous through guidance and conversation.
            CameraGlass(mode: .locate, cue: beepController.cue, mood: conversation.mood)

            if let path = outlinePath(in: stage.size) {
                ObjectOutline(path: path, style: outlineStyle, label: outlineLabel,
                              scanning: conversation.stage == .reading)
            }

            if guidanceStarted, camera.state == .running {
                HandGuidanceOverlay(skeletons: detector.handSkeletons,
                    outlines: [detector.leftHandJointPoints, detector.rightHandJointPoints],
                    measurements: [detector.leftHandEdge, detector.rightHandEdge].compactMap { $0 },
                    imageSize: segmenter.uprightImageSize)
            }
            Sprinkles(count: 6, quiet: true, unit: stage.unit)
            Confetti(trigger: celebrations, unit: stage.unit)
            GlassBackButton(action: onBack)
            statusBlob
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
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
            graceTask?.cancel()
            listenTask?.cancel()
            listener.stop()
        }
        .onReceive(segmenter.$objectMask) { mask in
            outline = mask.flatMap { MaskContour.outline(of: $0) }
        }
        .onChange(of: detector.approaching) { _, reached in
            if reached { celebrations += 1 }
        }
        .animation(.easeInOut, value: beepController.phase)
        .animation(.easeInOut, value: guidanceStarted)
        .animation(.easeInOut, value: conversation.stage)
        .animation(.easeInOut, value: conversation.agentStatus)
    }

    /// Whoever has the screen, in writing, in the glass panel at the bottom of it. For the three steps
    /// that is the distance the camera is measuring with the step under it — the step the voice announces
    /// and the chime marks, so a demo can be followed by someone who isn't wearing the headphones — and
    /// after the handoff the conversation's own state, which has nothing to measure.
    @ViewBuilder
    private var statusBlob: some View {
        switch conversation.stage {
        case .idle:
            if !guidanceStarted {
                StatusBlob(text: "Looking… · Tell Iris what to locate")
            } else if detector.objectClose {
                StatusBlob(text: "Close enough · Ready to explore")
            } else if detector.approaching {
                StatusBlob(text: "Got it! · Bring it closer to read")
            } else if outline == nil {
                StatusBlob(text: "Keep looking · Slowly move your phone around")
            } else if detector.handSkeletons.isEmpty {
                StatusBlob(text: "Hand not visible · Bring your hand into view")
            } else {
                StatusBlob(measurement: guidanceDistance.map { String(format: "%.1f m", $0) },
                           text: tooClose ? "Too close · Move it back" : guidanceDetail)
            }
        case .reading:
            ListeningIndicator(text: "Reading live…")
        case .talking:
            ListeningIndicator(status: conversation.agentStatus)
        case .ended:
            ListeningIndicator(text: "Say go back to finish")
        }
    }

    /// The live outline, aspect-filled onto the screen the way the camera preview is. Shown once Iris
    /// knows what it's looking for.
    private func outlinePath(in size: CGSize) -> Path? {
        guard guidanceStarted, let outline, outline.count > 2 else { return nil }
        let image = segmenter.uprightImageSize
        var path = Path()
        path.addLines(outline.map { MaskContour.aspectFill($0, image: image, view: size) })
        path.closeSubpath()
        return path
    }

    private var outlineStyle: ObjectOutline.Style {
        switch conversation.stage {
        case .reading: .reading
        case .talking, .ended: .settled
        case .idle: detector.approaching || detector.objectFound ? .success : .locate
        }
    }

    private var outlineLabel: String? {
        guard conversation.stage == .idle else { return nil }
        let name = target.prefix(1).uppercased() + target.dropFirst()
        if beepController.phase == .ready || detector.objectClose { return "Ready to read" }
        return detector.approaching || detector.objectFound ? "\(name) found" : name
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
        return nil // Camera-to-hand depth is not a fingertip-to-object measurement.
    }

    private var guidanceDetail: String {
        switch beepController.cue.direction {
        case .left: "Move your hand left"
        case .right: "Move your hand right"
        case .back: "Move your hand back"
        case .forward: "Move your hand forward"
        case nil: guidanceDistance == nil ? "Distance unavailable" : "Hand → " + target
        }
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

        graceTask?.cancel()
        let grace = Task {
            try? await Task.sleep(for: .seconds(namingGrace))
            guard !Task.isCancelled, !guidanceStarted else { return }
            listener.stop()
            beginGuidance()
        }
        graceTask = grace
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
