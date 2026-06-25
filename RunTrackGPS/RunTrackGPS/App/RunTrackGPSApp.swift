import SwiftUI

@main
struct RunTrackGPSApp: App {

    @StateObject private var viewModel = RunViewModel()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(viewModel)
                .onAppear {
                    // Configure the audio session up front so voice feedback works
                    // immediately (including in the background Audio mode).
                    viewModel.feedback.configureAudioSession()
                }
        }
    }
}
