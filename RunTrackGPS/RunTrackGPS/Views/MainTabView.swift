import SwiftUI

/// App root: a bottom-tab navigation (Tertiary Infotech house style) with the
/// run flow, run history, feedback, and about. The tab bar hides itself during an
/// active run / completion so those screens stay full-bleed (see `RootView`).
struct MainTabView: View {
    var body: some View {
        TabView {
            RootView()
                .tabItem { Label("Run", systemImage: "figure.run") }

            HistoryView(showsDoneButton: false)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .tint(.accentColor)
    }
}
