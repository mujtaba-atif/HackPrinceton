import Combine
import CoreGraphics
import Foundation

/// Continuously reads text from the camera, the way Probe's `TextReader` does: each scan feeds a
/// running merge, and `lines` is the clean, de-duplicated result in reading order.
///
/// Built on Turn to Read's pieces — `LabelCropPlanner` picks the region (the selected object, else the
/// center of the view), `LabelFrameProcessor` crops and recognizes off the main actor, and
/// `LabelTextAccumulator` merges lines across frames (a curved label is never readable in one shot).
/// A line counts once it has been seen in `minimumSightings` scans, which filters one-frame misreads.
@MainActor
final class LabelTextReader: ObservableObject {
    /// The part of the frame read when no object is selected, in Vision coordinates.
    static let region = LabelCropPlanner.centerRegion

    @Published private(set) var lines: [String] = []
    /// Same convention as Probe: landscape sensor turned upright for the portrait preview.
    @Published private(set) var uprightImageSize = CGSize(width: 1440, height: 1920)

    var minimumSightings = 2
    /// Box to read, Vision coordinates; nil reads `region`. Read each scan, so it can follow an object.
    var focus: (() -> CGRect?)?

    private let scanInterval: TimeInterval
    private let processor = LabelFrameProcessor()
    private let analyzer = LabelOrientationAnalyzer()
    private var accumulator = LabelTextAccumulator()
    private var isBusy = false
    private var lastScan: TimeInterval = 0
    private var generation = 0

    init(scanInterval: TimeInterval = 0.5) {
        self.scanInterval = scanInterval
    }

    /// Forgets everything read so far, so a rescan starts from an empty window.
    func reset() {
        generation += 1
        accumulator.reset()
        lines = []
    }

    func process(frame: CameraFrame) {
        uprightImageSize = CGSize(width: frame.imageResolution.height, height: frame.imageResolution.width)
        guard !isBusy, frame.timestamp - lastScan >= scanInterval else { return }
        isBusy = true
        lastScan = frame.timestamp
        let plan = LabelCropPlanner.plan(objectBox: focus?())
        let run = generation
        Task {
            defer { isBusy = false }
            guard let analysis = try? await processor.analyze(frame, plan: plan, level: .accurate),
                  run == generation else { return }
            accumulator.add(analyzer.usableLines(analysis.lines))
            let stable = accumulator.orderedLines
                .filter { $0.seenCount >= minimumSightings }
                .map(\.text)
            if stable != lines { lines = stable }
        }
    }
}
