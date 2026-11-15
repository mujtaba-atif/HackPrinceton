import SwiftUI

/// The revision 18 discovery screen: two full-width, equal-area choices sharing a diagonal edge.
/// The whole panel is tappable; camera routes replace the panel with the reference's short fade.
struct MainScreen: View {
    var onBack: () -> Void = {}

    @State private var audio = AudioLevels()
    @State private var optionChosen = false
    @State private var showFind = false
    @State private var showAnalyze = false
    @State private var listenTask: Task<Void, Never>?
    @StateObject private var listener = VoiceListener()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let question = "Are you looking for something, or do you want help exploring something?"
    private let commands: [String: [String]] = [
        "find": ["find", "locate", "position", "pinpoint", "looking for", "search"],
        "understand": ["understand", "analyze", "analyse", "analyzing", "interpret", "explore", "exploring"],
        "back": ["go back", "back", "return", "previous", "exit"],
        "repeat": ["repeat", "say that again", "one more time", "again", "pardon"]
    ]

    var body: some View {
        ZStack {
            if showFind {
                LocateScreen(onBack: { Speaker.shared.stop(); showFind = false })
            } else if showAnalyze {
                ExploreScreen(onBack: { Speaker.shared.stop(); showAnalyze = false })
            } else {
                options
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: showFind)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: showAnalyze)
        .navigationBarBackButtonHidden(true)
        #if DEBUG
        .task {
            switch UserDefaults.standard.string(forKey: "IrisPreviewScreen") {
            case "locate": showFind = true
            case "explore": showAnalyze = true
            default: break
            }
        }
        #endif
    }

    private var options: some View {
        StageView { stage in
            OptionsBackdrop()
            DiscoveryPanel(explore: false, stage: stage, action: chooseFind)
            DiscoveryPanel(explore: true, stage: stage, action: chooseUnderstand)
            Sprinkles(count: 20, unit: stage.unit)
            optionsGlass(stage)
            WaterWell(audio: audio, unit: stage.unit)
                .scaleEffect(0.7)
                .opacity(0.35)
                .placed(x: 120, y: 52, width: 200, height: 80, on: stage)
            GlassBackButton(action: onBack)
            ListeningIndicator(text: listener.isListening ? "Listening…" : Speaker.shared.isBusy ? "Iris is speaking…" : "Listening…",
                               speaking: Speaker.shared.isBusy)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .task {
            optionChosen = false
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, !optionChosen else { return }
            Speaker.shared.speak(question)
            await listenForCommands()
        }
        .onAppear { audio.start() }
        .onDisappear {
            audio.stop()
            listenTask?.cancel()
            listener.stop()
            if !showFind, !showAnalyze { Speaker.shared.stop() }
        }
    }

    @ViewBuilder
    private func optionsGlass(_ stage: Stage) -> some View {
        GlassFloat(cornerRadius: 15, sparkle: (20, 16, 11), unit: stage.unit)
            .modifier(GlassSkew(degrees: -10))
            .motion(Motion(7, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -5, y: -6, rotation: 14), to: Pose(x: 7, y: 13, rotation: 29)), unit: stage.unit)
            .modifier(RestingTilt(degrees: 19))
            .placed(x: 331, y: 80, width: 57, height: 55, on: stage)
        GlassFloat(unit: stage.unit)
            .modifier(GlassSkew(degrees: 9))
            .motion(Motion(8, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -6, y: 10, rotation: -22), to: Pose(x: 12, y: -12, rotation: -5)), unit: stage.unit)
            .modifier(RestingTilt(degrees: -19))
            .placed(x: -48, y: 390, width: 91, height: 69, on: stage)
    }

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
            case "find": chooseFind()
            case "understand": chooseUnderstand()
            case "back": onBack()
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

#Preview { MainScreen() }
