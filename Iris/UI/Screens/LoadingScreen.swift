import SwiftUI

/// Shown while `Preloader` loads the vision models: "Iris" with a spinning ring and what it's doing.
/// When the welcome screen is ready underneath it, `handedOver` fades this out and the welcome screen's
/// own title plays its light reveal.
struct LoadingScreen: View {
    /// What the preloader is doing, shown under the title.
    var step = "Getting ready"
    /// The home screen has taken over: nothing here is drawn any more.
    var handedOver = false

    var body: some View {
        StageView { stage in
            HomeBackdrop()
            Text("Iris")
                .font(IrisFont.nunito(stage(78), .black))
                .tracking(stage(-3))
                .foregroundStyle(IrisPalette.white)
                .placed(x: 0, y: 314, width: 360, height: 94, on: stage)
            VStack(spacing: stage(22)) {
                Spinner(unit: stage.unit)
                Text(step)
                    .font(IrisFont.nunito(stage(18), .bold))
                    .foregroundStyle(IrisPalette.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: step)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .placed(x: 0, y: 438, width: 360, height: 120, on: stage)
            Sprinkles(count: 20, unit: stage.unit)
        }
        .opacity(handedOver ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: handedOver)
        .ignoresSafeArea()
        .allowsHitTesting(!handedOver)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Iris is loading")
    }
}

/// A 44-point ring with a white top quarter, turning once a second.
private struct Spinner: View {
    var unit: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(IrisPalette.white, style: StrokeStyle(lineWidth: 6 * unit))
            .rotationEffect(.degrees(-135))
            .frame(width: 38 * unit, height: 38 * unit)
            .motion(Motion(1, curve: .linear, repeats: true, from: .rest, to: Pose(rotation: 360)))
    }
}

#Preview {
    LoadingScreen()
}
