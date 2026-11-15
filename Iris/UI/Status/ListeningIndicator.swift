import SwiftUI

/// The glass pill at the bottom of the screen: what Iris is doing, in a word or two. A breathing
/// microphone while it listens, bouncing voice bars while it speaks, and otherwise an icon for the state
/// (a timer for the countdown, a tick once text is read). It pops up from below when it appears.
struct ListeningIndicator: View {
    var text = "Listening…"
    var speaking = false
    /// An SF Symbol for a state that isn't listening or speaking; `nil` is the microphone.
    var systemImage: String?

    @Environment(\.irisUnit) private var unit

    var body: some View {
        HStack(spacing: 8 * unit) {
            if speaking {
                VoiceBars(unit: unit)
            } else {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 15 * unit, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    } else {
                        MicGlyph()
                    }
                }
                .frame(width: 18 * unit, height: 18 * unit)
                .motion(Motion(0.8, curve: .easeInOut, repeats: true, alternate: true,
                               from: Pose(scale: 0.92), to: Pose(scale: 1.1)))
            }
            Text(text)
                .font(IrisFont.nunito(15 * unit, .bold))
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .foregroundStyle(IrisPalette.white)
        .padding(.horizontal, 18 * unit)
        .padding(.vertical, 11 * unit)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay {
                    Capsule().fill(CSSLinearGradientStyle.pill)
                }
                .overlay { Capsule().strokeBorder(Color(rgba: 0xFAFCFF66), lineWidth: 1) }
                .shadow(color: Color(rgba: 0x061B3733), radius: 10 * unit, y: 8 * unit)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
        .motion(Motion(0.6, curve: Bezier(0.2, 0.8, 0.25, 1.35), from: Pose(y: 45, scale: 0.75, opacity: 0)), unit: unit)
        .padding(.bottom, 32 * unit)
        .transition(.opacity)
    }
}

/// The pill's tinted glass: deep navy fading toward the navy at the far end.
enum CSSLinearGradientStyle {
    static let pill = LinearGradient(colors: [Color(rgba: 0x092653CC), Color(rgba: 0x123A7388)],
                                     startPoint: UnitPoint(x: 0.1, y: 0.2), endPoint: UnitPoint(x: 0.9, y: 0.8))
}

extension ListeningIndicator {
    init(status: AgentSession.Status) {
        switch status {
        case .speaking: self.init(text: "Iris is speaking…", speaking: true)
        case .thinking: self.init(text: "Thinking…", systemImage: "ellipsis")
        case .connecting: self.init(text: "Connecting…", systemImage: "antenna.radiowaves.left.and.right")
        case .listening, .idle: self.init()
        }
    }
}
