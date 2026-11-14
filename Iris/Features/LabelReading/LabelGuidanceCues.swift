import AudioToolbox
import UIKit

/// Non-speech feedback while guiding. Swap in the team's spatial sound effects by conforming to this.
@MainActor
protocol LabelGuidanceCueing: AnyObject {
    func prepare()
    /// Called repeatedly while guiding; `readiness` is 0...1 and the caller speeds up ticks as it rises.
    func tick(readiness: Double)
    func success()
    func failure()
}

/// Placeholder cues: a light haptic plus a soft system click that strengthens as the label comes into view.
@MainActor
final class HapticLabelCuePlayer: LabelGuidanceCueing {
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        impact.prepare()
        notification.prepare()
    }

    func tick(readiness: Double) {
        impact.impactOccurred(intensity: CGFloat(0.35 + 0.65 * min(max(readiness, 0), 1)))
        AudioServicesPlaySystemSound(1104)
    }

    func success() {
        notification.notificationOccurred(.success)
    }

    func failure() {
        notification.notificationOccurred(.error)
    }
}
