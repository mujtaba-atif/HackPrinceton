import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    IrisMark()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 30)

                    VoiceFirstBadge()
                        .padding(.bottom, 18)

                    Text("Iris")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(IrisTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Find what’s nearby. Reach with confidence.")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(IrisTheme.accent)
                        .padding(.top, 8)

                    Text("Iris is designed to help you locate physical objects and move your hand toward them with simple, spoken directions.")
                        .font(.body)
                        .foregroundStyle(IrisTheme.secondaryText)
                        .lineSpacing(5)
                        .padding(.top, 16)

                    NavigationLink {
                        ExploreView()
                    } label: {
                        PrimaryActionLabel(
                            title: "Start Exploring",
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(IrisPrimaryButtonStyle())
                    .padding(.top, 32)
                    .accessibilityLabel("Start Exploring")
                    .accessibilityHint("Opens the Iris exploration experience")

                    #if DEBUG
                    NavigationLink {
                        HandTrackingDebugView()
                    } label: {
                        Label("Hand tracking debug", systemImage: "hand.raised")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(IrisTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .padding(.top, 12)
                    .accessibilityHint("Developer screen for testing hand tracking")

                    #endif

                    Label(
                        "Camera and voice access will only be requested when a feature needs it.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(IrisTheme.secondaryText)
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, IrisTheme.screenPadding)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .irisScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}

