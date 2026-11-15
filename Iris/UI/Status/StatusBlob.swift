import SwiftUI

/// The glass status panel at the bottom of the camera screens: a big line on top (how far, or the headline
/// of what is happening) and a smaller one under it. It pops in from the right and hovers gently.
///
/// While guidance has the screen the big line is the distance being measured and the small one the step
/// the voice has announced; with nothing measured, a step label such as "Step 2 of 3 · Move across" is
/// split at its "·" into the two lines.
struct StatusBlob: View {
    /// The big line: what was measured. `nil` while nothing is.
    var measurement: String?
    /// Where that measurement has to get to ("→ 10 in"), on the last step. Smaller, beside it.
    var goal: String?
    /// What is happening, in the same words the voice uses.
    var text: String
    /// An SF Symbol for the step, breathing beside the small line (or the big one when there is no small
    /// line), so the step reads at a glance.
    var systemImage: String?
    /// Brightens the rim once the thing it is reporting has been reached.
    var highlighted = false

    @Environment(\.irisUnit) private var unit

    private var lines: (head: String, detail: String?) {
        if let measurement { return (measurement, text) }
        let parts = text.components(separatedBy: " · ")
        if parts.count == 2 { return (parts[0], parts[1]) }
        return (text, nil)
    }

    var body: some View {
        let (head, detail) = lines
        let shape = RoundedRectangle(cornerRadius: 29 * unit, style: .continuous)
        VStack(spacing: 2 * unit) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * unit) {
                if detail == nil, let systemImage { icon(systemImage, size: 22) }
                Text(head)
                    .font(IrisFont.nunito(34 * unit, .black).monospacedDigit())
                    .tracking(-1 * unit)
                if let goal {
                    Text(goal)
                        .font(IrisFont.nunito(17 * unit, .bold).monospacedDigit())
                        .opacity(0.75)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            if let detail {
                HStack(spacing: 6 * unit) {
                    if let systemImage { icon(systemImage, size: 14) }
                    Text(detail)
                        .font(IrisFont.nunito(15 * unit, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .contentTransition(.numericText())
        .foregroundStyle(IrisPalette.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20 * unit)
        .padding(.vertical, 18 * unit)
        .frame(width: 270 * unit)
        .frame(minHeight: 101 * unit)
        .background {
            shape
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    shape.fill(LinearGradient(colors: [Color(rgba: 0x297FDBCC), Color(rgba: 0x123A73B3)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(alignment: .topLeading) {
                    // The thin highlight along the top edge.
                    LinearGradient(colors: [.clear, Color(rgba: 0xFAFCFF99), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 90 * unit, height: 1)
                        .offset(x: 20 * unit, y: 10 * unit)
                }
                .overlay {
                    shape.strokeBorder(highlighted ? IrisPalette.ice : Color(rgba: 0xE7F5FFAA),
                                       lineWidth: highlighted ? 2 : 1)
                }
                .shadow(color: Color(rgba: 0x061B3740), radius: 15 * unit, y: 14 * unit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([measurement, goal.map { "goal \($0)" }, text].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.updatesFrequently)
        .motion(Motion(4.5, delay: 0.7, curve: .easeInOut, repeats: true, alternate: true, from: .rest, to: Pose(y: -5)),
                unit: unit)
        .motion(Motion(0.7, curve: Bezier(0.2, 0.8, 0.25, 1.3), from: Pose(x: 90, y: 20, scale: 0.6, opacity: 0)),
                unit: unit)
        .animation(.easeInOut(duration: 0.3), value: highlighted)
        .padding(.bottom, 45 * unit)
        .transition(.opacity)
    }
}

extension StatusBlob {
    /// The conversation half of the screen.
    init(status: AgentSession.Status) {
        switch status {
        case .speaking: self.init(text: "Iris is speaking…", systemImage: "speaker.wave.2.fill")
        case .thinking: self.init(text: "Thinking…", systemImage: "ellipsis")
        case .connecting: self.init(text: "Connecting…", systemImage: "antenna.radiowaves.left.and.right")
        case .listening, .idle: self.init(text: "Listening…", systemImage: "mic.fill")
        }
    }

    private func icon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * unit, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
            .motion(Motion(0.8, curve: .easeInOut, repeats: true, alternate: true,
                           from: Pose(scale: 0.92), to: Pose(scale: 1.12)))
    }
}
