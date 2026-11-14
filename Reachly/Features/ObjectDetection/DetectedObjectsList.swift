import SwiftUI
import UIKit

struct DetectedObjectsList: View {
    @ObservedObject var detection: ObjectDetectionService
    var spatialEstimate: SpatialTargetEstimate? = nil
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Detected objects")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                switch detection.readiness {
                case .preparing:
                    Text("Loading object detection…")
                case let .unavailable(reason):
                    Text(reason)
                    Button("Retry Object Detection", action: retry)
                        .frame(minHeight: 44)
                case .ready:
                    if detection.latestObjects.isEmpty {
                        Text("No objects detected. Slowly point the camera around you.")
                    }
                case .planned:
                    Text("Object detection is paused.")
                }

                if let target = detection.selectedTarget {
                    SpatialTargetReadout(target: target, estimate: spatialEstimate)
                    Text(target.state == .tracking
                         ? "Target: \(target.object.name)"
                         : "Target lost: \(target.object.name). Find it again or select another object.")
                        .font(.body.weight(.semibold))
                    Button("Clear Target", action: detection.clearSelection)
                        .frame(minHeight: 44)
                }

                ForEach(detection.latestObjects) { object in
                    let selected = detection.selectedTarget?.object.id == object.id
                    Button { detection.select(object.id) } label: {
                        HStack {
                            Text(object.name.capitalized)
                            Spacer()
                            Text(object.confidence, format: .percent.precision(.fractionLength(0)))
                            if selected { Image(systemName: "checkmark.circle.fill") }
                        }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 48)
                        .padding(.horizontal, 12)
                        .background(ReachlyTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(object.name), \(Int((object.confidence * 100).rounded())) percent confidence")
                    .accessibilityHint("Selects this object as your target")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ReachlyTheme.screenPadding)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 230)
        .foregroundStyle(ReachlyTheme.primaryText)
        .tint(ReachlyTheme.accent)
        .background(ReachlyTheme.surface.opacity(0.96))
        .onChange(of: detection.selectedTarget) { old, new in
            guard old?.object.id != new?.object.id || old?.state != new?.state else { return }
            let message: String
            if let new {
                if new.state == .lost {
                    message = "Target lost: \(new.object.name)"
                } else if old?.object.id == new.object.id {
                    message = "Target found: \(new.object.name)"
                } else {
                    message = "Target selected: \(new.object.name)"
                }
            } else {
                message = "Target cleared"
            }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}
