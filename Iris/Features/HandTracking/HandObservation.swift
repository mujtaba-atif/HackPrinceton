import CoreGraphics
import Foundation

/// The 21 hand landmarks Vision reports, independent of the Vision framework so models stay testable.
enum HandJoint: String, CaseIterable, Hashable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    static let fingertips: [HandJoint] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
    static let knuckles: [HandJoint] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]

    /// Each finger from tip down to its base joint. When Vision misses a tip (often when it is
    /// pressed against or hidden behind an object), the most distal confident joint stands in.
    static let fingerChains: [[HandJoint]] = [
        [.thumbTip, .thumbIP, .thumbMP, .thumbCMC],
        [.indexTip, .indexDIP, .indexPIP, .indexMCP],
        [.middleTip, .middleDIP, .middlePIP, .middleMCP],
        [.ringTip, .ringDIP, .ringPIP, .ringMCP],
        [.littleTip, .littleDIP, .littlePIP, .littleMCP]
    ]

    /// Skeleton segments for drawing, each finger chained back to the wrist.
    static let bones: [(HandJoint, HandJoint)] = fingerChains.flatMap { chain -> [(HandJoint, HandJoint)] in
        let ordered = Array(chain.reversed()) // base -> tip
        var segments = [(HandJoint.wrist, ordered[0])]
        for index in 1..<ordered.count {
            segments.append((ordered[index - 1], ordered[index]))
        }
        return segments
    } + [(.indexMCP, .middleMCP), (.middleMCP, .ringMCP), (.ringMCP, .littleMCP)]
}

/// One joint position in **upright, normalized image space with a top-left origin**
/// (x right, y down, 0...1), matching how the portrait camera preview is displayed.
struct HandLandmark: Equatable, Sendable {
    let joint: HandJoint
    let location: CGPoint
    let confidence: Double
}

enum HandChirality: String, Equatable, Sendable {
    case left
    case right
    case unknown

    var mirrored: HandChirality {
        switch self {
        case .left: .right
        case .right: .left
        case .unknown: .unknown
        }
    }

    var title: String {
        switch self {
        case .left: "Left hand"
        case .right: "Right hand"
        case .unknown: "Hand"
        }
    }
}

enum HandTrackingState: Equatable, Sendable {
    /// Running, but no hand has been seen recently.
    case searching
    /// A confident, well-formed hand pose in the latest frame.
    case tracking
    /// Seen in the latest frame, but with low confidence or too few joints to rely on.
    case limited
    /// Missing from recent frames; the last smoothed pose is retained briefly to ride out dropouts.
    case lost
    /// The camera is paused, interrupted, or stopped.
    case suspended

    var isUsable: Bool { self == .tracking }

    var title: String {
        switch self {
        case .searching: "Looking for your hand"
        case .tracking: "Hand tracked"
        case .limited: "Hand partly visible"
        case .lost: "Hand lost"
        case .suspended: "Hand tracking paused"
        }
    }
}

/// A smoothed, identity-stable hand. All points use upright normalized top-left image space.
struct HandObservation: Identifiable, Equatable, Sendable {
    let id: UUID
    let chirality: HandChirality
    let landmarks: [HandJoint: HandLandmark]
    /// Approximate palm center (middle knuckle, or the wrist/knuckle mean when it is missing).
    let center: CGPoint
    /// The index fingertip, or its most distal confident stand-in.
    let indexTip: CGPoint?
    /// The best single point for reaching: the index tip when available, else any extended fingertip.
    let pointingTip: CGPoint?
    /// Mean confidence over all 21 joints (missing joints count as zero).
    let confidence: Double
    let state: HandTrackingState
    /// Timestamp of the frame that produced this pose.
    let timestamp: TimeInterval
    /// Timestamp of the last frame in which this hand was actually detected.
    let lastSeen: TimeInterval

    var wrist: HandLandmark? { landmarks[.wrist] }

    var fingertips: [HandLandmark] {
        HandJoint.fingertips.compactMap { landmarks[$0] }
    }
}

/// Everything the UI or future guidance needs from one processed frame.
struct HandTrackingSnapshot: Equatable, Sendable {
    var hands: [HandObservation] = []
    var uprightImageSize: CGSize = .zero
    var timestamp: TimeInterval?
    var isSuspended = true

    /// The hand most worth guiding: confidently tracked first, then highest confidence.
    var primaryHand: HandObservation? {
        hands.max { lhs, rhs in
            if lhs.state.isUsable != rhs.state.isUsable { return !lhs.state.isUsable }
            return lhs.confidence < rhs.confidence
        }
    }

    var overallState: HandTrackingState {
        if isSuspended { return .suspended }
        return primaryHand?.state ?? .searching
    }
}
