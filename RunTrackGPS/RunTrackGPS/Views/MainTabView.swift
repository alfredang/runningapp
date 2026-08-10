import SwiftUI

/// App root: a bottom-tab navigation (Tertiary Infotech house style) with the
/// run flow, run history, feedback, and about. The tab bar hides itself during an
/// active run / completion so those screens stay full-bleed (see `RootView`).
struct MainTabView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    /// Observed so a theme change in Settings retints the whole tab bar immediately.
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            RootView()
                .tabItem { Label("Run", systemImage: "figure.run") }
                .tag(AppTab.run)

            HistoryView(showsDoneButton: false)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)

            FeedbackView()
                .tabItem { Label("Feedback", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.feedback)

            AboutView()
                .tabItem { Label("About", systemImage: "info.circle.fill") }
                .tag(AppTab.about)
        }
        .tint(Theme.accent)
    }
}
