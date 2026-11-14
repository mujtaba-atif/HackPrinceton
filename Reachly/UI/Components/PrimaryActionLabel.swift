import SwiftUI

struct PrimaryActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.headline.weight(.bold))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 12)

            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
        }
        .foregroundStyle(Color.black.opacity(0.88))
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, minHeight: 64)
        .contentShape(Rectangle())
    }
}

struct ReachlyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: ReachlyTheme.controlCornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? ReachlyTheme.accent.opacity(0.78) : ReachlyTheme.accent)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ReachlyTheme.controlCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
    }
}

