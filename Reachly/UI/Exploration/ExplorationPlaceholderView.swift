import SwiftUI

struct ExplorationPlaceholderView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ReachlyMark(size: 104)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 38)

                Label("Foundation ready", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ReachlyTheme.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(ReachlyTheme.accentSoft, in: Capsule())
                    .accessibilityElement(children: .combine)

                Text("Exploration is next")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(ReachlyTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("The camera, object search, hand tracking, and spoken guidance will connect here in the next stage of development.")
                    .font(.body)
                    .foregroundStyle(ReachlyTheme.secondaryText)
                    .lineSpacing(5)

                Label("No camera or microphone is active", systemImage: "lock.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ReachlyTheme.primaryText)
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(ReachlyTheme.raisedSurface)
                    )
                    .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, ReachlyTheme.screenPadding)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .reachlyScreenBackground()
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ExplorationPlaceholderView()
    }
    .preferredColorScheme(.dark)
}

