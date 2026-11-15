import SwiftUI

extension EnvironmentValues {
    /// Screen points per design point (`Stage.unit`), for controls laid out outside a `StageView`.
    @Entry var irisUnit: CGFloat = 1
}

/// The round glass back button, top left, that sweeps in from the edge.
struct GlassBackButton: View {
    var action: () -> Void

    @Environment(\.irisUnit) private var unit

    var body: some View {
        Button(action: action) {
            Text("‹")
                .font(IrisFont.nunito(32 * unit, .semibold))
                .foregroundStyle(.white)
                .offset(y: -2 * unit)
                .frame(width: 54 * unit, height: 54 * unit)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.35))
                        .overlay {
                            Circle().fill(LinearGradient(colors: [Color(rgba: 0xFAFCFF30), Color(rgba: 0xB5DEFA0D)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay { Circle().strokeBorder(Color(rgba: 0xFAFCFF75), lineWidth: 1) }
                        .shadow(color: Color(rgba: 0x061B3720), radius: 10 * unit, y: 8 * unit)
                }
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Go back")
        .motion(Motion(0.65, curve: .easeOut, from: Pose(x: -90, opacity: 0)), unit: unit)
        .padding(.leading, 24 * unit)
        .padding(.top, 60 * unit)
    }
}

/// The design's press feedback: a quick springy shrink.
struct GlassPressStyle: ButtonStyle {
    var pressed: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressed : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// The design's microphone glyph (24 × 24 viewBox).
struct MicGlyph: View {
    var body: some View {
        Canvas { context, size in
            let k = min(size.width, size.height) / 24
            context.scaleBy(x: k, y: k)
            context.fill(Path(roundedRect: CGRect(x: 8, y: 2, width: 8, height: 13), cornerRadius: 4), with: .foreground)
            var stand = Path()
            stand.move(to: CGPoint(x: 5, y: 10))
            stand.addLine(to: CGPoint(x: 5, y: 12))
            stand.addArc(center: CGPoint(x: 12, y: 12), radius: 7, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            stand.addLine(to: CGPoint(x: 19, y: 10))
            stand.move(to: CGPoint(x: 12, y: 19))
            stand.addLine(to: CGPoint(x: 12, y: 22))
            stand.move(to: CGPoint(x: 9, y: 22))
            stand.addLine(to: CGPoint(x: 15, y: 22))
            context.stroke(stand, with: .foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// Five little bars bouncing while Iris speaks.
struct VoiceBars: View {
    var unit: CGFloat = 1

    var body: some View {
        HStack(spacing: 3 * unit) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .frame(width: 3 * unit, height: 18 * unit)
                    .motion(Motion(0.6, delay: Double(i) * 0.11, repeats: true, alternate: true,
                                   from: Pose(scaleX: 1, scaleY: 6 / 18), to: .rest))
            }
        }
        .frame(height: 18 * unit)
    }
}
