import SwiftUI

struct ReachlyMark: View {
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            Circle()
                .fill(ReachlyTheme.surface)

            Circle()
                .stroke(ReachlyTheme.hairline, lineWidth: 1)
                .padding(12)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.04, to: 0.21)
                    .stroke(
                        ReachlyTheme.accent.opacity(1 - Double(index) * 0.22),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .padding(CGFloat(index) * 13 + 18)
                    .rotationEffect(.degrees(-46))
            }

            Image(systemName: "hand.raised.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(ReachlyTheme.primaryText)
                .offset(x: -8, y: 9)

            Circle()
                .fill(ReachlyTheme.accent)
                .frame(width: 14, height: 14)
                .shadow(color: ReachlyTheme.accent.opacity(0.55), radius: 10)
                .offset(x: size * 0.28, y: -size * 0.27)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

