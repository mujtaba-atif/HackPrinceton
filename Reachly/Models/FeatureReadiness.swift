import Foundation

enum ReachlyFeature: String, CaseIterable, Sendable {
    case cameraAR
    case objectDetection
    case handTracking
    case guidance
    case voice

    var title: String {
        switch self {
        case .cameraAR: "Camera and AR"
        case .objectDetection: "Object detection"
        case .handTracking: "Hand tracking"
        case .guidance: "Guidance"
        case .voice: "Voice"
        }
    }
}

enum FeatureReadiness: Equatable, Sendable {
    case planned
    case preparing
    case ready
    case unavailable(reason: String)
}

struct ExplorationCapabilities: Equatable, Sendable {
    let readiness: [ReachlyFeature: FeatureReadiness]

    static let foundation = ExplorationCapabilities(
        readiness: Dictionary(
            uniqueKeysWithValues: ReachlyFeature.allCases.map { ($0, .planned) }
        )
    )
}

