import SwiftUI

/// The object-shaped boundary drawn over the camera: a soft halo with a crisp line on it, traced from
/// the real segmentation mask in Locate (never a bounding rectangle), and around the reading area in
/// Explore. The translucent green tint and scanning light stay clipped to the live silhouette.
struct ObjectOutline: View, Animatable {
    enum Style {
        /// Locate, looking at the object.
        case locate
        /// Reached: a brighter green fill.
        case success
        /// Explore, looking for text.
        case explore
        /// Explore, text found and being read.
        case reading
        /// After the read, while Iris talks: slightly faded.
        case settled

        var color: Color {
            switch self {
            case .locate, .reading, .settled, .explore, .success: Color(rgba: 0x6FF1B1FF)
            }
        }

        var lineWidth: CGFloat { 2.2 }

    }

    /// The outline, in this view's coordinates.
    var path: Path
    var style: Style
    var label: String?
    var scanning = false
    /// 0…1 of the shape filled with light from the bottom up.
    var fill: Double = 0

    @Environment(\.irisUnit) private var unit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// The fill is drawn in a `Canvas`, which reads it raw; animating it here is what lets
    /// `withAnimation(.linear(duration:))` run the countdown's rise smoothly.
    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    var body: some View {
        let box = path.boundingRect
        ZStack(alignment: .topLeading) {
            path.fill(Color(rgba: 0x6FF1B1FF).opacity(style == .success ? 0.25 : 0.19))
            if fill > 0 {
                Canvas { context, _ in
                    context.clip(to: path)
                    let level = CGRect(x: box.minX, y: box.maxY - box.height * fill, width: box.width, height: box.height * fill)
                    context.fill(Path(level), with: .linearGradient(
                        Gradient(colors: [IrisPalette.sky.opacity(0.10), IrisPalette.sky.opacity(0.28)]),
                        startPoint: CGPoint(x: level.midX, y: level.minY), endPoint: CGPoint(x: level.midX, y: level.maxY)))
                    var line = Path()
                    line.move(to: CGPoint(x: level.minX, y: level.minY))
                    line.addLine(to: CGPoint(x: level.maxX, y: level.minY))
                    context.stroke(line, with: .color(IrisPalette.ice), lineWidth: 2.5 * unit)
                }
            }
            if scanning, !reduceMotion, box.height > 0 {
                ScanLight(box: box, unit: unit)
                    .clipShape(path)
            }
            path
                .trim(from: 0, to: revealed ? 1 : 0)
                .stroke(style.color, style: StrokeStyle(lineWidth: 8 * unit, lineCap: .round, lineJoin: .round))
                .opacity(0.18)
                .blur(radius: 2 * unit)
            path
                .trim(from: 0, to: revealed ? 1 : 0)
                .stroke(style.color, style: StrokeStyle(lineWidth: style.lineWidth * unit, lineCap: .round, lineJoin: .round))
            if let label, box.width > 0 {
                Text(label)
                    .font(IrisFont.nunito(13 * unit, .extraBold))
                    .foregroundStyle(IrisPalette.white)
                    .padding(.horizontal, 12 * unit)
                    .padding(.vertical, 5 * unit)
                    .background(Color(rgba: 0x10372FFF), in: RoundedRectangle(cornerRadius: 8 * unit))
                    .overlay { RoundedRectangle(cornerRadius: 8 * unit).stroke(Color(rgba: 0x6FF1B166), lineWidth: unit) }
                    .fixedSize()
                    .position(x: box.midX, y: max(80 * unit, box.minY - 22 * unit))
            }
        }
        .opacity(style == .settled ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.3), value: style)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 0.7)) { revealed = true }
            }
        }
    }
}

/// A band of light that sweeps down through the object and back (`object-surface-scan`, 3.4 s).
private struct ScanLight: View {
    let box: CGRect
    let unit: CGFloat

    var body: some View {
        let band = 38 * unit
        ZStack(alignment: .bottom) {
            Rectangle().fill(IrisPalette.sky.opacity(0.16))
            Rectangle().fill(IrisPalette.ice).frame(height: 2.5 * unit)
        }
        .frame(width: box.width, height: band)
        .motion(Motion(3.4, curve: .easeInOut, repeats: true, alternate: true,
                       from: Pose(x: box.minX, y: box.minY - band), to: Pose(x: box.minX, y: box.maxY)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
