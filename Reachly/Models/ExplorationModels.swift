import Foundation

struct NormalizedPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct NormalizedRegion: Equatable, Sendable {
    let origin: NormalizedPoint
    let width: Double
    let height: Double
}

struct DetectedObject: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let confidence: Double
    let region: NormalizedRegion

    init(
        id: UUID = UUID(),
        name: String,
        confidence: Double,
        region: NormalizedRegion
    ) {
        self.id = id
        self.name = name
        self.confidence = confidence
        self.region = region
    }
}

enum HandSide: String, Equatable, Sendable {
    case left
    case right
    case unknown
}

struct TrackedHand: Identifiable, Equatable, Sendable {
    let id: UUID
    let side: HandSide
    let focusPoint: NormalizedPoint

    init(id: UUID = UUID(), side: HandSide, focusPoint: NormalizedPoint) {
        self.id = id
        self.side = side
        self.focusPoint = focusPoint
    }
}

enum GuidanceDirection: String, Equatable, Sendable {
    case forward
    case backward
    case left
    case right
    case hold
    case complete
}

struct GuidanceInstruction: Identifiable, Equatable, Sendable {
    let id: UUID
    let direction: GuidanceDirection
    let spokenPhrase: String

    init(
        id: UUID = UUID(),
        direction: GuidanceDirection,
        spokenPhrase: String
    ) {
        self.id = id
        self.direction = direction
        self.spokenPhrase = spokenPhrase
    }
}

