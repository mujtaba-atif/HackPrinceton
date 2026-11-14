import SwiftUI

struct ObjectDetectionOverlay: View {
    let snapshot: DetectionSnapshot
    let select: (UUID) -> Void

    var body: some View {
        GeometryReader { geometry in
            ForEach(snapshot.objects) { object in
                let rect = DetectionGeometry.viewRect(object.boundingBox,
                    imageSize: snapshot.uprightImageSize, viewport: geometry.size)
                let visible = rect.intersection(CGRect(origin: .zero, size: geometry.size))
                let selected = snapshot.selectedTarget?.object.id == object.id
                if !visible.isNull, !visible.isEmpty {
                    Button { select(object.id) } label: {
                        Rectangle()
                            .fill(Color.clear)
                            .overlay {
                                Rectangle().strokeBorder(selected ? Color.yellow : ReachlyTheme.accent,
                                                          lineWidth: selected ? 4 : 2)
                            }
                            .overlay(alignment: .topLeading) {
                                Text((selected ? "✓ " : "") + object.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.black.opacity(0.8))
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: visible.width, height: visible.height)
                    .position(x: visible.midX, y: visible.midY)
                    // The equivalent list provides larger, stable VoiceOver targets.
                    .accessibilityHidden(true)
                }
            }
        }
        .clipped()
    }
}
