import SwiftUI

/// Draws hand outlines, skeleton, joints, palm center, and pointing fingertip over a camera preview.
/// The preview and this overlay must share one viewport (including safe-area extensions),
/// the same contract as `ObjectDetectionOverlay`.
struct HandTrackingOverlay: View {
    let snapshot: HandTrackingSnapshot
    var mirrored = false
    var showsSkeleton = true

    var body: some View {
        Canvas { context, size in
            for hand in snapshot.hands {
                draw(hand, in: &context, viewport: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ hand: HandObservation, in context: inout GraphicsContext, viewport: CGSize) {
        let opacity = Self.opacity(for: hand.state)
        guard opacity > 0 else { return }
        let color = hand.state == .tracking ? IrisTheme.accent : Color.white
        func view(_ point: CGPoint) -> CGPoint {
            HandGeometry.imageToView(point, imageSize: snapshot.uprightImageSize, viewport: viewport, mirrored: mirrored)
        }

        let points = hand.landmarks.mapValues { view($0.location) }

        // Outline
        let hull = HandGeometry.convexHull(Array(points.values))
        if hull.count > 2 {
            var outline = Path()
            outline.addLines(hull)
            outline.closeSubpath()
            context.fill(outline, with: .color(color.opacity(0.12 * opacity)))
            context.stroke(outline, with: .color(color.opacity(0.7 * opacity)),
                           style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: hand.state == .tracking ? [] : [6, 5]))
        }

        // Skeleton
        if showsSkeleton {
            var bones = Path()
            for (from, to) in HandJoint.bones {
                guard let a = points[from], let b = points[to] else { continue }
                bones.move(to: a)
                bones.addLine(to: b)
            }
            context.stroke(bones, with: .color(color.opacity(0.85 * opacity)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }

        // Joints, sized by confidence
        for (joint, landmark) in hand.landmarks {
            guard let point = points[joint] else { continue }
            let radius = 2.5 + 2 * landmark.confidence
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(.white.opacity(opacity)))
        }

        // Palm center ring
        let center = view(hand.center)
        let ring = Path(ellipseIn: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
        context.stroke(ring, with: .color(color.opacity(opacity)), lineWidth: 3)

        // Pointing fingertip marker
        if let tip = hand.pointingTip.map(view) {
            let marker = Path(ellipseIn: CGRect(x: tip.x - 9, y: tip.y - 9, width: 18, height: 18))
            context.fill(marker, with: .color(Color.yellow.opacity(opacity)))
            context.stroke(marker, with: .color(.black.opacity(0.6 * opacity)), lineWidth: 2)
        }
    }

    private static func opacity(for state: HandTrackingState) -> Double {
        switch state {
        case .tracking: 1
        case .limited: 0.6
        case .lost: 0.3
        case .searching, .suspended: 0
        }
    }
}

#Preview {
    HandTrackingOverlay(snapshot: .preview)
        .background(IrisTheme.background)
        .preferredColorScheme(.dark)
}

extension HandTrackingSnapshot {
    /// A static open-palm hand for previews and layout checks.
    static var preview: HandTrackingSnapshot {
        let raw: [(HandJoint, CGFloat, CGFloat)] = [
            (.wrist, 0.50, 0.78),
            (.thumbCMC, 0.42, 0.72), (.thumbMP, 0.36, 0.66), (.thumbIP, 0.32, 0.61), (.thumbTip, 0.29, 0.56),
            (.indexMCP, 0.44, 0.60), (.indexPIP, 0.42, 0.52), (.indexDIP, 0.41, 0.47), (.indexTip, 0.40, 0.42),
            (.middleMCP, 0.50, 0.59), (.middlePIP, 0.50, 0.50), (.middleDIP, 0.50, 0.45), (.middleTip, 0.50, 0.40),
            (.ringMCP, 0.56, 0.60), (.ringPIP, 0.57, 0.52), (.ringDIP, 0.58, 0.47), (.ringTip, 0.59, 0.43),
            (.littleMCP, 0.61, 0.63), (.littlePIP, 0.63, 0.57), (.littleDIP, 0.64, 0.53), (.littleTip, 0.65, 0.50)
        ]
        var landmarks: [HandJoint: HandLandmark] = [:]
        for (joint, x, y) in raw {
            landmarks[joint] = HandLandmark(joint: joint, location: CGPoint(x: x, y: y), confidence: 0.9)
        }
        let hand = HandObservation(id: UUID(), chirality: .right, landmarks: landmarks,
                                   center: CGPoint(x: 0.5, y: 0.59), indexTip: CGPoint(x: 0.40, y: 0.42),
                                   pointingTip: CGPoint(x: 0.40, y: 0.42), confidence: 0.9,
                                   state: .tracking, timestamp: 1, lastSeen: 1)
        return HandTrackingSnapshot(hands: [hand], uprightImageSize: CGSize(width: 1440, height: 1920),
                                    timestamp: 1, isSuspended: false)
    }
}
