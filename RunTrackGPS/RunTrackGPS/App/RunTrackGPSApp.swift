import SwiftUI

@main
struct RunTrackGPSApp: App {

    @StateObject private var viewModel = RunViewModel()
    /// Drives a re-render of the whole tree when the accent palette changes.
    @ObservedObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(viewModel)
                // The app commits to a single warm light-grey look (see `Theme`), so
                // it stays bright and legible outdoors regardless of the device's
                // dark-mode setting — the previous all-black screens came from
                // following the system appearance.
                .preferredColorScheme(.light)
                .tint(Theme.accent)
                .onAppear {
                    // Configure the audio session up front so voice feedback works
                    // immediately (including in the background Audio mode).
                    viewModel.feedback.configureAudioSession()
                }
        }
    }
}
