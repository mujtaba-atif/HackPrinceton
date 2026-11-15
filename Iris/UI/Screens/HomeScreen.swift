import SwiftUI

struct HomeScreen: View {
    /// False while the loading screen is still up over this one (so it can lay out and draw unseen).
    /// Turning it true plays the entrance: the title's light reveal, the tagline, then the crew. It isn't
    /// replayed when coming back from the main screen.
    var introStarted = true

    @State private var hasIntroduced = false
    @StateObject private var listener = VoiceListener()

    @State private var showMainScreen = false
    #if DEBUG
    /// Developer screens (the original Explore, hand tracking): long-press the home screen.
    @State private var showsDeveloperScreens = false
    #endif
    /// The glass wipe is crossing to the options screen.
    @State private var wiping = false
    @State private var confetti = 0

    /// The main screen *replaces* this one as the stack's root rather than being pushed onto it: a push
    /// slides the new screen in from the side, which UIKit runs and `disablesAnimations` can't stop. The
    /// glass wipe is the transition instead, and swapping the root under it has nothing to suppress.
    var body: some View {
        NavigationStack {
            ZStack {
                if showMainScreen {
                    MainScreen(onBack: { swap(toMain: false) })
                } else {
                    home
                }
                Confetti(trigger: confetti)
                if wiping {
                    GlassWipe {
                        swap(toMain: true)
                        // The options screen paints over the sheet on its first frame; a beat later the
                        // sheet goes.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { wiping = false }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .background(VolumeHUDHider())
        #if DEBUG
        // `-IrisPreviewScreen main|locate|explore` opens straight onto a screen, for screenshots.
        .task {
            if UserDefaults.standard.string(forKey: "IrisPreviewScreen") != nil { swap(toMain: true) }
        }
        #endif
        #if DEBUG
        .fullScreenCover(isPresented: $showsDeveloperScreens) {
            HomeView()
                .tint(IrisTheme.accent)
                .preferredColorScheme(.dark)
                .overlay(alignment: .topTrailing) {
                    Button("Close") { showsDeveloperScreens = false }
                        .font(.headline)
                        .padding()
                }
        }
        #endif
    }

    /// Swaps the stack's root without any animation.
    private func swap(toMain: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showMainScreen = toMain }
    }

    private func proceed() {
        guard !wiping, !showMainScreen else { return }
        confetti += 1
        wiping = true
    }

    private var home: some View {
        StageView { stage in
            HomeBackdrop()
            if introStarted {
                Sprinkles(count: 20, unit: stage.unit)
                homeGlass(stage)
                PrismText(text: "Iris", font: IrisFont.nunito(stage(78), .black), tracking: -3, timing: .brand,
                          unit: stage.unit)
                    .accessibilityAddTraits(.isHeader)
                    .placed(x: 0, y: 128, width: 360, height: 94, on: stage)
                PrismText(text: "See beyond the surface", font: IrisFont.nunito(stage(22), .bold), tracking: -0.5,
                          timing: .tagline, unit: stage.unit)
                    .placed(x: 0, y: 216, width: 360, height: 30, on: stage)
                Crew(stage: stage)
                SwipeHint(unit: stage.unit, listening: listener.isListening, action: proceed)
                    .placed(x: 75, y: 704, width: 210, height: 82, on: stage)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onEnded { value in
                    let isVerticalSwipe = abs(value.translation.height) > abs(value.translation.width)
                    if isVerticalSwipe && value.translation.height < -60 {
                        proceed()
                    }
                }
        )
        .task(id: introStarted) {
            guard introStarted else { return }
            if !hasIntroduced {
                try? await Task.sleep(for: .seconds(0.25))
                guard !Task.isCancelled else { return }
                hasIntroduced = true
                Speaker.shared.speak("Hello, this is Iris. I can help you find things around you, or help you understand an item you're holding!")
            }
            await Speaker.shared.waitUntilIdle()
            guard !Task.isCancelled else { return }
            await listener.start(
                commands: ["continue": ["continue", "okay", "next", "start", "begin", "go", "yes", "ready"]]
            ) { _ in proceed() }
        }
        .onDisappear { listener.stop() }
        #if DEBUG
        .onLongPressGesture(minimumDuration: 2) { showsDeveloperScreens = true }
        #endif
    }

    /// The two floating panes on the welcome screen.
    @ViewBuilder
    private func homeGlass(_ stage: Stage) -> some View {
        GlassFloat(sparkle: (28, 22, 22), unit: stage.unit)
            .modifier(GlassSkew(degrees: -10))
            .motion(Motion(7, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -5, y: -6, rotation: 14), to: Pose(x: 7, y: 13, rotation: 29)),
                    unit: stage.unit)
            .modifier(RestingTilt(degrees: 19))
            .placed(x: 288, y: 34, width: 86, height: 90, on: stage)
        GlassFloat(unit: stage.unit)
            .modifier(GlassSkew(degrees: 9))
            .motion(Motion(8, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(x: -6, y: 10, rotation: -22), to: Pose(x: 12, y: -12, rotation: -5)),
                    unit: stage.unit)
            .modifier(RestingTilt(degrees: -19))
            .placed(x: -33, y: 271, width: 91, height: 69, on: stage)
    }
}

/// The tilt a floating pane keeps when its orbit stops under reduced motion.
struct RestingTilt: ViewModifier {
    var degrees: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(reduceMotion ? degrees : 0))
    }
}

/// "swipe up" with two chevrons nudging upward; tapping it continues too. While Iris is listening for
/// "continue", the label becomes the glass listening pill, so the screen shows the microphone is open.
private struct SwipeHint: View {
    var unit: CGFloat
    var listening = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5 * unit) {
                ZStack {
                    Chevron(top: 3)
                        .stroke(IrisPalette.white.opacity(0.45), style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))
                    Chevron(top: 21)
                        .stroke(IrisPalette.white, style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 26 * unit, height: 32 * unit)
                    .frame(height: 34 * unit)
                    .motion(Motion(1.4, curve: .easeInOut, repeats: true, alternate: true, from: .rest, to: Pose(y: -9)),
                            unit: unit)
                Text("swipe up")
                    .font(IrisFont.nunito(16 * unit, .black))
                    .foregroundStyle(IrisPalette.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue")
        .accessibilityHint("Or swipe up, or say continue")
        .motion(Motion(0.7, delay: 1.5, from: Pose(opacity: 0)))
    }
}

/// One upward chevron of the design's 30 × 38 pair, its point at `top`.
private struct Chevron: Shape {
    var top: CGFloat

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 30, sy = rect.height / 38
        var path = Path()
        path.move(to: CGPoint(x: 3 * sx, y: (top + 12) * sy))
        path.addLine(to: CGPoint(x: 15 * sx, y: top * sy))
        path.addLine(to: CGPoint(x: 27 * sx, y: (top + 12) * sy))
        return path
    }
}

#Preview {
    HomeScreen()
}
