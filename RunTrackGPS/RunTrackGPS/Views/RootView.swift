import SwiftUI

/// Top-level screen router. Switches between the three screens and hosts the
/// shared alert presentation.
struct RootView: View {
    @EnvironmentObject private var viewModel: RunViewModel

    var body: some View {
        Group {
            switch viewModel.screen {
            case .home:
                HomeView()
            case .running:
                RunView()
            case .completion:
                CompletionView()
            }
        }
        .animation(.easeInOut, value: viewModel.screen)
        .alert(item: $viewModel.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
