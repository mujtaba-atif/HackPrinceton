import SwiftUI

/// The glass pill at the bottom of the screen: what Iris is doing, in a word or two, with a breathing
/// microphone — or bouncing voice bars while Iris is speaking. It pops up from below when it appears.
struct ListeningIndicator: View {
    var text = "Listening…"
    var speaking = false

    @Environment(\.irisUnit) private var unit

    var body: some View {
        HStack(spacing: 8 * unit) {
            if speaking {
                VoiceBars(unit: unit)
            } else {
                MicGlyph()
                    .frame(width: 18 * unit, height: 18 * unit)
                    .motion(Motion(1.6, curve: .easeInOut, repeats: true, alternate: true,
                                   from: .rest, to: Pose(scale: 1.05)))
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
        case .thinking: self.init(text: "Thinking…")
        case .connecting: self.init(text: "Connecting…")
        case .listening, .idle: self.init()
        }
    }
}
