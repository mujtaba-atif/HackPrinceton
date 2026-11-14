import SwiftUI

@main
struct IrisApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(IrisTheme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

