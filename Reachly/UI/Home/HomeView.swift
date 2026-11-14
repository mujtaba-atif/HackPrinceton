import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ReachlyMark()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 30)

                    VoiceFirstBadge()
                        .padding(.bottom, 18)

                    Text("Reachly")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(ReachlyTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Find what’s nearby. Reach with confidence.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ReachlyTheme.accent)
                        .padding(.top, 8)

                    Text("Reachly is designed to help you locate physical objects and move your hand toward them with simple, spoken directions.")
                        .font(.body)
                        .foregroundStyle(ReachlyTheme.secondaryText)
                        .lineSpacing(5)
                        .padding(.top, 16)

                    NavigationLink {
                        ExplorationPlaceholderView()
                    } label: {
                        PrimaryActionLabel(
                            title: "Start Exploring",
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(ReachlyPrimaryButtonStyle())
                    .padding(.top, 32)
                    .accessibilityLabel("Start Exploring")
                    .accessibilityHint("Opens the Reachly exploration experience")

                    Label(
                        "Camera and voice access will only be requested when a feature needs it.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(ReachlyTheme.secondaryText)
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, ReachlyTheme.screenPadding)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .reachlyScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}

