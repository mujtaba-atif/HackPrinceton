import SwiftUI

struct SpatialTargetReadout: View {
    let target: SelectedObjectTarget
    let estimate: SpatialTargetEstimate?

    private var current: SpatialTargetEstimate? {
        guard target.state == .tracking, estimate?.objectID == target.object.id else { return nil }
        return estimate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let current, current.validity == .measured, let meters = current.distanceMeters {
                Text("\(target.object.name.capitalized) — approximately \(meters.formatted(.number.precision(.fractionLength(1)))) meters away")
                    .font(.body.weight(.semibold))
            } else {
                Text("\(target.object.name.capitalized) — Distance unavailable")
                    .font(.body.weight(.semibold))
                if case let .unavailable(reason) = current?.validity {
                    Text(reason.message).font(.footnote)
                }
            }
            if let current, current.horizontalPosition != .unknown, current.verticalPosition != .unknown {
                Text("\(horizontalText(current.horizontalPosition)), \(verticalText(current.verticalPosition))")
                    .font(.footnote)
            }
        }
        .foregroundStyle(ReachlyTheme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // The label updates without interrupting VoiceOver speech on every measurement.
    }

    private func horizontalText(_ position: HorizontalPosition) -> String {
        switch position {
        case .left: "left of camera center"
        case .right: "right of camera center"
        case .center: "horizontally centered"
        case .unknown: "horizontal position unavailable"
        }
    }

    private func verticalText(_ position: VerticalPosition) -> String {
        switch position {
        case .above: "above camera center"
        case .below: "below camera center"
        case .center: "vertically centered"
        case .unknown: "vertical position unavailable"
        }
    }
}
