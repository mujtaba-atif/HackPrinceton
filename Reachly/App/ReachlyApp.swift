import SwiftUI

@main
struct ReachlyApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(ReachlyTheme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

