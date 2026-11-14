import SwiftUI

struct VoiceFirstBadge: View {
    var body: some View {
        Label("Voice-first by design", systemImage: "waveform")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ReachlyTheme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(ReachlyTheme.accentSoft)
            )
            .overlay {
                Capsule()
                    .stroke(ReachlyTheme.accent.opacity(0.34), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

