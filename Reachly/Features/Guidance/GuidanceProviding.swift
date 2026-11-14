import Foundation

/// Boundary for the future deterministic guidance state machine.
/// It will coordinate spoken, visual, and haptic cues without owning camera work.
@MainActor
protocol GuidanceProviding: AnyObject {
    var readiness: FeatureReadiness { get }
    var latestInstruction: GuidanceInstruction? { get }

    func reset()
}

