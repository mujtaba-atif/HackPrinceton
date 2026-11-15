import SwiftUI

/// Builds what the screens need before the app shows any of them, while `LoadingScreen` is up.
///
/// Two things would otherwise be built lazily on the main thread the moment a screen appeared, and both
/// showed as a hitch: the artwork (`IrisArtwork` parses the design's SVGs on first use) and the CoreML
/// models (loaded in the detectors' `init`, so tapping Locate stalled the push into `LocateScreen`).
@MainActor
final class Preloader: ObservableObject {
    @Published private(set) var isReady = false
    /// True once the home screen has been on screen (under the loading screen) long enough to have drawn.
    @Published private(set) var isRevealed = false
    /// What `LoadingScreen` says it's doing.
    @Published private(set) var step = "Getting ready"

    /// Keeps the loading screen up long enough to be read rather than flashing past on a warm launch.
    private let minimumDuration = Duration.milliseconds(1600)

    func warm() async {
        guard !isReady else { return }
        let started = ContinuousClock.now

        step = "Drawing the artwork"
        await Task.detached(priority: .userInitiated) { Self.buildArtwork() }.value

        step = "Loading the vision models"
        await Task.detached(priority: .userInitiated) { Self.loadModels() }.value

        step = "Ready"
        let elapsed = ContinuousClock.now - started
        if elapsed < minimumDuration {
            try? await Task.sleep(for: minimumDuration - elapsed)
        }
        isReady = true
        // Let the home screen lay out and draw while it is still covered.
        try? await Task.sleep(for: .milliseconds(300))
        isRevealed = true
    }

    /// Touching each piece of artwork parses its SVG.
    private nonisolated static func buildArtwork() {
        let art = [IrisArtwork.locateCard, IrisArtwork.exploreCard, IrisArtwork.skye, IrisArtwork.pip,
                   IrisArtwork.nova, IrisArtwork.echo, IrisArtwork.treasureMap, IrisArtwork.edgeLights,
                   IrisArtwork.locatePanel, IrisArtwork.explorePanel]
        _ = art.map(\.viewBox)
    }

    private nonisolated static func loadModels() {
        do {
            if let segmentation = try ModelStore.model(names: [SegmentationDetector.defaultModelName]) {
                ModelStore.prime(segmentation)
            }
            // Bundled but disabled (`ObjectDetector.yoloEnabled`), so it isn't primed — just loaded,
            // so flipping it back on doesn't put the load back in the way of the navigation.
            _ = try ModelStore.model(names: ObjectDetector.objectModelNames)
        } catch {
            print("Preloader: model warmup failed: \(error)")
        }
    }
}
