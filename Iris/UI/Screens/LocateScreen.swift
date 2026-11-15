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
    /// Finds things the detector has no class for (pills, keys, a pill bottle among bottles) by how they look.
    @StateObject private var appearanceSearch = AppearanceSearch()
    @Environment(\.scenePhase) private var scenePhase

    @State private var listenTask: Task<Void, Never>?
    @State private var startTask: Task<Void, Never>?
    @State private var frameTask: Task<Void, Never>?
    /// Working out how to find the target (`prepareSearch`), and the wait for a new name after one Iris
    /// couldn't picture. Both held so leaving the screen cancels them: a stray one would start guidance,
    /// and its voice and tone, on a screen that has already gone.
    @State private var searchTask: Task<Void, Never>?
    @State private var askTask: Task<Void, Never>?
    @State private var guidanceStarted = false
    /// What this screen guides to, once named.
    @State private var target: String?
    /// The target as the screen says it (`AppearanceSearchPhrases.speakable`): never a word that would
    /// be heard as "go back".
    @State private var spokenTarget = "object"

    /// How the target is being found. `nil` until `prepareSearch` has decided, during which the
    /// detector must not pick a stand-in: "pill bottle" would otherwise select the first bottle it saw.
    enum SearchMode: Equatable {
        /// The detector has a class for it; its selected detection is the target.
        case detector
        /// Found by how it looks; the appearance search's confirmed match is the target. Restarts with the camera.
        case appearance(TargetAppearance)
    }
    @State private var searchMode: SearchMode?
    @State private var announcedMatch = false
    @State private var lastHintAt: TimeInterval = -.infinity
    /// Seconds between "it may be over to the left" lines while nothing has been confirmed.
    private let hintGap: TimeInterval = 8

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
                AppearanceMatchOverlay(match: appearanceSearch.match, imageSize: appearanceSearch.uprightImageSize)
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
        .onChange(of: appearanceSearch.match != nil) { _, found in
            guard found, !announcedMatch, let match = appearanceSearch.match else { return }
            announcedMatch = true
            Speaker.shared.speak(AppearanceSearchPhrases.found(spokenTarget, match: match))
        }
        .onChange(of: appearanceSearch.hint) { _, hint in
            // A window of the frame looked like it, but nothing has been confirmed: say which way to turn
            // the camera, now and then, so the search isn't silent while the user sweeps the room.
            guard let hint, appearanceSearch.match == nil, !Speaker.shared.isBusy else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastHintAt >= hintGap else { return }
            lastHintAt = now
            Speaker.shared.speak(AppearanceSearchPhrases.hint(spokenTarget, box: hint))
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
        switch searchMode {
        case .detector:
            if let selected = snapshot.selectedTarget {
                snapshot.objects = snapshot.objects.filter { $0.id == selected.object.id }
            }
        case .appearance:
            snapshot.objects = []
        case nil:
            // Everything, while there is no target yet; nothing while Iris is still deciding how to find it.
            if target != nil { snapshot.objects = [] }
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
    private func askForTarget(askingFirst: Bool = true) async {
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, target == nil else { return }
        if askingFirst { Speaker.shared.speak(question) }
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, target == nil else { return }

        let grace = Task {
            try? await Task.sleep(for: .seconds(namingGrace))
            guard !Task.isCancelled, target == nil else { return }
            listener.stop()
            let fallback = detection.latestObjects.first?.name ?? Self.anyObject
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
                beginGuidance(to: name.isEmpty ? (detection.latestObjects.first?.name ?? Self.anyObject) : name)
            }
        )
    }

    /// The target when nothing has been named and nothing is detected: whatever the detector finds first.
    private static let anyObject = "object"

    /// Hands the screen to `DistanceBeepController` for good — it owns the voice and the tone from
    /// here — and leaves the recogniser listening for one word.
    private func beginGuidance(to name: String) {
        guard !guidanceStarted else { return }
        guidanceStarted = true
        target = name
        spokenTarget = AppearanceSearchPhrases.speakable(name, avoiding: backKeywords)
        print("Locate: guiding to \(name)")
        beepController.setTarget(spokenTarget)
        listenForBack()
        searchTask?.cancel()
        searchTask = Task {
            guard await prepareSearch(for: name), !Task.isCancelled else { return }
            beepController.begin()
        }
    }

    /// Decides how to find the target. The detector handles its own classes; anything else is described
    /// (catalog, then the on-device language model) and searched for by appearance. Returns false when
    /// nothing is known about it, after asking the user to describe it instead — the screen is never
    /// left silent with a name it can't use.
    private func prepareSearch(for name: String) async -> Bool {
        let quick = AppearanceCatalog.appearance(for: name, classifierLabels: AppearanceScanner.classifierLabels)
        // "object" is the stand-in when no one has named anything and nothing is detected yet: there is
        // nothing to describe, so the detector guides to whatever it finds, as it always did. Describing
        // it would fail, re-ask, and fall back to it again every `namingGrace`, for good.
        if name == Self.anyObject || quick?.usesDetector == true {
            searchMode = .detector
            return true
        }
        if quick == nil || quick?.source == .words, AppearanceDescriber.languageModelAvailable {
            Speaker.shared.speak(AppearanceSearchPhrases.thinking(about: spokenTarget))
        }
        let described = await AppearanceDescriber.describe(name)
        guard !Task.isCancelled else { return false }
        guard let appearance = described, appearance.isSearchable || appearance.usesDetector else {
            Speaker.shared.speak(AppearanceSearchPhrases.unknown(spokenTarget))
            askAgain()
            return false
        }
        if appearance.usesDetector {
            searchMode = .detector
            return true
        }
        var spoken = appearance
        spoken.name = spokenTarget
        searchMode = .appearance(appearance)
        announcedMatch = false
        if camera.state == .running { startAppearanceSearch(appearance) }
        Speaker.shared.speak(AppearanceSearchPhrases.searching(for: spoken))
        return true
    }

    /// Listens for a new name or description after one Iris couldn't picture.
    private func askAgain() {
        guidanceStarted = false
        target = nil
        searchMode = nil
        listenTask?.cancel()
        listener.stop()
        askTask?.cancel()
        askTask = Task { await askForTarget(askingFirst: false) }
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
                if searchMode == .detector { selectTargetIfNeeded() }
                tracker.update(frame: frame, target: guidanceTargetBox, hands: hands.snapshot.hands)
                beepController.update(
                    leftEdge: tracker.leftHandEdge,
                    rightEdge: tracker.rightHandEdge,
                    objectFound: tracker.objectFound,
                    approaching: tracker.approaching,
                    objectClose: tracker.objectClose,
                    objectCenter: guidanceTargetBox.map { CGPoint(x: $0.midX, y: $0.midY) }
                )
            }
        }
        if case .appearance(let appearance) = searchMode, !appearanceSearch.isActive {
            startAppearanceSearch(appearance)
        }
    }

    /// The detector's selected object, or what the appearance search found; nothing until Iris has
    /// decided which.
    private var guidanceTargetBox: CGRect? {
        switch searchMode {
        case .detector: detection.selectedTarget?.currentBoundingBox
        case .appearance: appearanceSearch.match?.box
        case nil: nil
        }
    }

    private func startAppearanceSearch(_ appearance: TargetAppearance) {
        appearanceSearch.start(appearance, frames: camera.makeFrameStream(), detections: { detection.latestObjects })
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
        appearanceSearch.stop()
    }

    private func tearDown() {
        searchTask?.cancel()
        askTask?.cancel()
        listenTask?.cancel()
        listener.stop()
        conversation.stop()
        appearanceSearch.stop()
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
