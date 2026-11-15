import SwiftUI

/// "How can Iris help you?": the Locate card springs in from the left and the Explore card from the
/// right, each resting at an opposite 2° tilt and floating on its own rhythm. The ripples in the open
/// water above them answer the microphone, so they stir as the user speaks.
///
/// It takes `HomeScreen`'s place as the root of its NavigationStack (don't nest another one here), so
/// going back is `onBack` rather than `dismiss()` — see `HomeScreen.body`.
struct MainScreen: View {
    var onBack: () -> Void = {}

    /// When the Explore card, the last thing to arrive, has landed: its spring's delay plus duration.
    private static let cardsLanded = 0.38 + 1.25

    @State private var audio = AudioLevels()
    @State private var optionChosen = false
    @State private var showFind = false
    @State private var showAnalyze = false
    @State private var listenTask: Task<Void, Never>?
    @StateObject private var listener = VoiceListener()

    private let question = "Are you looking for something, or do you want help exploring something?"
    private let commands: [String: [String]] = [
        "find": ["find", "locate", "position", "pinpoint", "looking for", "search"],
        "understand": ["understand", "analyze", "analyse", "analyzing", "interpret", "explore", "exploring"],
        "repeat": ["repeat", "say that again", "one more time", "again", "pardon"]
    ]

    var body: some View {
        StageView { stage in
            OptionsBackdrop()
            Sprinkles(count: 20, unit: stage.unit)
            optionsGlass(stage)

            PrismText(text: "How can Iris help you?", font: IrisFont.nunitoSans(stage(34), .bold), tracking: -0.4,
                      timing: .question, breakBeforeWord: 3, lineSpacing: -5.6, unit: stage.unit)
                .accessibilityAddTraits(.isHeader)
                .placed(x: 10, y: 116, width: 340, height: 88, on: stage)

            WaterWell(audio: audio, unit: stage.unit)
                .opacity(0.6)
                .placed(x: 80, y: 215, width: 200, height: 80, on: stage)

            Button(action: chooseFind) {
                LocateCard()
                    .shadow(color: Color(rgba: 0x061B3724), radius: 9 * stage.unit, y: 18 * stage.unit)
                    .motion(Motion(6.4, curve: .easeInOut, repeats: true, [
                        (0, Pose(rotation: -2)), (0.25, Pose(x: -3, y: -7, rotation: -2.8)),
                        (0.5, Pose(y: -2, rotation: -2)), (0.75, Pose(x: 3, y: 6, rotation: -1.2)), (1, Pose(rotation: -2)),
                    ]), unit: stage.unit)
                    .modifier(RestingTilt(degrees: -2))
                    .background(FloatRipples(cornerRadius: 23 * stage.unit, delay: 1.35))
                    .modifier(TiltDrift(drift: 14 * stage.unit))
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Locate an object")
            .accessibilityHint("Or say locate")
            .motion(Motion(1.15, delay: 0.2, curve: Bezier(0.16, 0.7, 0.2, 1), [
                (0, Pose(x: -390, y: -35, rotation: -18, scale: 0.7, opacity: 0)),
                (0.65, Pose(x: 15, rotation: 3, scale: 1.04)),
                (0.83, Pose(x: -6, rotation: -1, scale: 0.98)),
                (1, .rest),
            ]), unit: stage.unit)
            .placed(x: 14, y: 322, width: 305, height: 177, on: stage)

            Button(action: chooseUnderstand) {
                ExploreCard()
                    .shadow(color: Color(rgba: 0x061B3724), radius: 9 * stage.unit, y: 18 * stage.unit)
                    .motion(Motion(7.2, delay: -0.9, curve: .easeInOut, repeats: true, [
                        (0, Pose(rotation: 2)), (0.25, Pose(x: 3, y: 6, rotation: 2.8)),
                        (0.5, Pose(y: 2, rotation: 2)), (0.75, Pose(x: -3, y: -7, rotation: 1.2)), (1, Pose(rotation: 2)),
                    ]), unit: stage.unit)
                    .modifier(RestingTilt(degrees: 2))
                    .background(FloatRipples(cornerRadius: 23 * stage.unit, delay: 1.63))
                    .modifier(TiltDrift(drift: 14 * stage.unit))
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Explore an object")
            .accessibilityHint("Or say explore")
            .motion(Motion(1.25, delay: 0.38, curve: Bezier(0.16, 0.7, 0.2, 1), [
                (0, Pose(x: 390, y: 60, rotation: 19, scale: 0.65, opacity: 0)),
                (0.65, Pose(x: -15, y: -3, rotation: -3, scale: 1.05)),
                (0.83, Pose(x: 6, y: 2, rotation: 1, scale: 0.98)),
                (1, .rest),
            ]), unit: stage.unit)
            .placed(x: 41, y: 534, width: 305, height: 177, on: stage)

            GlassBackButton(action: onBack)

            if listener.isListening {
                ListeningIndicator()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut, value: listener.isListening)
        .navigationDestination(isPresented: $showFind) {
            LocateScreen(onBack: { showFind = false })
        }
        .navigationDestination(isPresented: $showAnalyze) {
            ExploreScreen(onBack: { showAnalyze = false })
        }
        .onChange(of: showFind) { _, isShowing in
            if !isShowing { Speaker.shared.stop() }
        }
        .onChange(of: showAnalyze) { _, isShowing in
            if !isShowing { Speaker.shared.stop() }
        }
        .task {
            optionChosen = false
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "IrisPreviewScreen") {
            case "locate": showFind = true; return
            case "explore": showAnalyze = true; return
            default: break
            }
            #endif
            // Held until the cards have landed: starting to speak costs the main thread a little (see
            // `Speaker.play`), and mid-spring that shows as a hitch.
            try? await Task.sleep(for: .seconds(Self.cardsLanded + 0.15))
            guard !Task.isCancelled, !optionChosen else { return }
            Speaker.shared.speak(question)
            await listenForCommands()
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { audio.start() }
        .onDisappear {
            audio.stop()
            listenTask?.cancel()
            listener.stop()
            // Not when this screen is leaving because it pushed Locate or Explore: a push fires this
            // *after* the destination has appeared and started talking, and stopping here would cut its
            // first line off. Coming back from either is the `onChange` pair above; this is for going home.
            if !showFind, !showAnalyze { Speaker.shared.stop() }
        }
    }

    /// The two smaller panes on the options screen.
    @ViewBuilder
    private func optionsGlass(_ stage: Stage) -> some View {
        GlassFloat(cornerRadius: 15, sparkle: (20, 16, 11), unit: stage.unit)
            .motion(Motion(7, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -5, y: -6, rotation: 14), to: Pose(x: 7, y: 13, rotation: 29)),
                    unit: stage.unit)
            .modifier(RestingTilt(degrees: 19))
            .placed(x: 285, y: 230, width: 57, height: 55, on: stage)
        GlassFloat(unit: stage.unit)
            .motion(Motion(8, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -6, y: 10, rotation: -22), to: Pose(x: 12, y: -12, rotation: -5)),
                    unit: stage.unit)
            .modifier(RestingTilt(degrees: -19))
            .placed(x: -27, y: 448, width: 91, height: 69, on: stage)
    }
}

extension MainScreen {
    private func choose(announcing message: String) {
        optionChosen = true
        listener.stop()
        Speaker.shared.stop()
        Speaker.shared.speak(message)
    }

    private func chooseFind() {
        choose(announcing: "Locate object selected")
        showFind = true
    }

    private func chooseUnderstand() {
        choose(announcing: "Explore object selected")
        showAnalyze = true
    }

    private func listenForCommands() async {
        await Speaker.shared.waitUntilIdle()
        guard !Task.isCancelled, !optionChosen else { return }
        await listener.start(commands: commands) { command in
            switch command {
            case "find":
                chooseFind()
            case "understand":
                chooseUnderstand()
            default:
                Speaker.shared.speak(question)
                listenTask = Task { await listenForCommands() }
            }
        }
    }
}

/// The open water between the question and the cards: three rings rippling out on a slow beat, plus a
/// ring for every drop the microphone shakes loose (`AudioLevels`), so it stirs as the user speaks. Its
/// own view so the drops redraw only this.
private struct WaterWell: View {
    var audio: AudioLevels
    var unit: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let ring = Bezier.ease

    var body: some View {
        let drops = audio.drops
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = CGSize(width: 100 * unit, height: 30 * unit)
                // The beat: 2.8 s each, 0.8 s apart; scale .15 → 2, opacity 0 → .7 (20%) → 0.
                for delay in [0.0, 0.8, 1.6] {
                    let p = reduceMotion ? 0.3 : ((t - delay) / 2.8).truncatingRemainder(dividingBy: 1)
                    guard p >= 0 else { continue }
                    let scale = 0.15 + 1.85 * Self.ring(p)
                    let opacity = p < 0.2 ? 0.7 * Self.ring(p / 0.2) : 0.7 * (1 - Self.ring((p - 0.2) / 0.8))
                    ring(&context, at: center, size: base, scale: scale, opacity: opacity)
                }
                guard !reduceMotion else { return }
                // The voice: a ring wherever a drop lands.
                for drop in drops {
                    let age = (now - drop.born) / drop.life
                    guard age >= 0, age < 1 else { continue }
                    let at = CGPoint(x: drop.at.x * size.width, y: drop.at.y * size.height)
                    let scale = 0.15 + (0.6 + 1.2 * drop.reach) * Bezier.easeOut(age)
                    ring(&context, at: at, size: CGSize(width: base.width * 0.6, height: base.height * 0.6),
                         scale: scale, opacity: Double(drop.strength) * 0.9 * (1 - age))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ring(_ context: inout GraphicsContext, at center: CGPoint, size: CGSize, scale: Double, opacity: Double) {
        let rect = CGRect(x: center.x - size.width * scale / 2, y: center.y - size.height * scale / 2,
                          width: size.width * scale, height: size.height * scale)
        context.stroke(Path(ellipseIn: rect), with: .color(Color(rgba: 0xE7F5FF80).opacity(opacity)),
                       lineWidth: 2 * unit)
    }
}

#Preview {
    NavigationStack { MainScreen() }
}
