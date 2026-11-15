import SwiftUI
import Vision

/// The reference's 21 landmarks and fingertip connector, driven by live Vision/LiDAR evidence.
/// Missing joints break their bone segment; unavailable depth never becomes a made-up distance.
struct HandGuidanceOverlay: View {
    typealias Joint = VNHumanHandPoseObservation.JointName
    var skeletons: [[Joint: CGPoint]]
    var outlines: [[CGPoint]] = []
    var measurements: [EdgeMeasurement]
    var imageSize: CGSize
    var showsLostState = true
    @Environment(\.irisUnit) private var unit

    static let chains: [[Joint]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.indexMCP, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.middleMCP, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.ringMCP, .littleMCP, .littlePIP, .littleDIP, .littleTip],
        [.wrist, .littleMCP], [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
    ]

    private var nearest: EdgeMeasurement? {
        measurements.min { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for outline in outlines where outline.count > 2 {
                        var ghost = Path()
                        ghost.addLines(outline.map { project($0, in: geo.size) })
                        ghost.closeSubpath()
                        context.fill(ghost, with: .color(IrisPalette.sky.opacity(0.07)))
                        context.stroke(ghost, with: .color(IrisPalette.ice.opacity(0.35)),
                                       style: StrokeStyle(lineWidth: 1.2 * unit, lineJoin: .round))
                    }
                    for skeleton in skeletons {
                        let points = skeleton.mapValues { project($0, in: geo.size) }
                        for chain in Self.chains {
                            var bone = Path()
                            var connected = false
                            for joint in chain {
                                guard let point = points[joint] else { connected = false; continue }
                                if connected { bone.addLine(to: point) } else { bone.move(to: point) }
                                connected = true
                            }
                            context.stroke(bone, with: .color(IrisPalette.sky.opacity(0.2)), style: StrokeStyle(lineWidth: 6 * unit, lineCap: .round))
                            context.stroke(bone, with: .color(Color(rgba: 0xBDEEFFFF)), style: StrokeStyle(lineWidth: 1.8 * unit, lineCap: .round))
                        }
                        for (joint, point) in points {
                            let radius = (joint == .indexTip ? 4.5 : 2.8) * unit
                            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                            context.fill(dot, with: .color(joint == .indexTip ? Color(rgba: 0x6FF1B1FF) : IrisPalette.white))
                            context.stroke(dot, with: .color(Color(rgba: 0x248DB2FF)), lineWidth: 1.3 * unit)
                        }
                    }
                    if !skeletons.isEmpty, let nearest {
                        let tip = project(nearest.fingertip, in: geo.size)
                        let edge = project(nearest.edge, in: geo.size)
                        var line = Path(); line.move(to: edge); line.addLine(to: tip)
                        context.stroke(line, with: .color(Color(rgba: 0x72E6CE2E)), lineWidth: 6 * unit)
                        context.stroke(line, with: .color(Color(rgba: 0xADFFE1FF)), style: StrokeStyle(lineWidth: 1.7 * unit, dash: [3 * unit, 4 * unit]))
                        let ring = Path(ellipseIn: CGRect(x: edge.x - 5.5 * unit, y: edge.y - 5.5 * unit, width: 11 * unit, height: 11 * unit))
                        context.fill(ring, with: .color(Color(rgba: 0x0B3035FF)))
                        context.stroke(ring, with: .color(Color(rgba: 0x6FF1B1FF)), lineWidth: 2 * unit)
                    }
                }
                ForEach(Array(skeletons.enumerated()), id: \.offset) { _, skeleton in
                    if let tip = skeleton[.indexTip] {
                        Circle().stroke(Color(rgba: 0x6FF1B1FF), lineWidth: 1.5 * unit)
                            .frame(width: 18 * unit, height: 18 * unit)
                            .opacity(0.65)
                            .motion(Motion(2.3, curve: .easeOut, repeats: true, [
                                (0, Pose(scale: 0.8, opacity: 0.7)),
                                (0.75, Pose(scale: 1.6, opacity: 0)), (1, Pose(scale: 1.6, opacity: 0))
                            ]))
                            .position(project(tip, in: geo.size))
                    }
                }
                if !skeletons.isEmpty {
                    if let nearest, let distance = nearest.distance, distance.isFinite {
                        let tip = project(nearest.fingertip, in: geo.size)
                        let edge = project(nearest.edge, in: geo.size)
                        Text(String(format: "%.1f m", distance))
                            .font(IrisFont.nunito(13 * unit, .black).monospacedDigit())
                            .foregroundStyle(Color(rgba: 0xEBFFF6FF))
                            .padding(.horizontal, 9 * unit).frame(minWidth: 58 * unit, minHeight: 30 * unit)
                            .background(Color(rgba: 0x092D2EEB), in: RoundedRectangle(cornerRadius: 12 * unit))
                            .overlay { RoundedRectangle(cornerRadius: 12 * unit).stroke(Color(rgba: 0xA4FFD780), lineWidth: unit) }
                            .position(x: min(max((tip.x + edge.x) / 2, 35 * unit), geo.size.width - 35 * unit),
                                      y: min(max((tip.y + edge.y) / 2, 110 * unit), geo.size.height - 165 * unit))
                    }
                    HStack(spacing: 5 * unit) {
                        Circle().fill(Color(rgba: 0x6FF1B1FF)).frame(width: 5 * unit, height: 5 * unit)
                        Text("Hand tracked").font(IrisFont.nunito(9 * unit, .extraBold))
                    }
                    .padding(.horizontal, 8 * unit).padding(.vertical, 5 * unit)
                    .background(Color(rgba: 0x092653C9), in: RoundedRectangle(cornerRadius: 10 * unit))
                    .overlay { RoundedRectangle(cornerRadius: 10 * unit).stroke(Color(rgba: 0xB5DEFA44), lineWidth: unit) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16 * unit).offset(y: 618 * unit)
                } else if showsLostState {
                    Text("Bring your hand into view")
                        .font(IrisFont.nunito(11 * unit, .extraBold))
                        .padding(.horizontal, 11 * unit).padding(.vertical, 8 * unit)
                        .background(Color(rgba: 0x092653CF), in: RoundedRectangle(cornerRadius: 12 * unit))
                        .overlay { RoundedRectangle(cornerRadius: 12 * unit).stroke(Color(rgba: 0xB5DEFA55), lineWidth: unit) }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 18 * unit).offset(y: 590 * unit)
                }
            }
            .foregroundStyle(IrisPalette.ice)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func project(_ point: CGPoint, in size: CGSize) -> CGPoint {
        MaskContour.aspectFill(CGPoint(x: point.x, y: 1 - point.y), image: imageSize, view: size)
    }
}
