import SwiftUI

/// Post-run summary with Save / Start New Run actions.
struct CompletionView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @State private var didSave = false

    private var session: RunSession? { viewModel.completedSession }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Headline
            VStack(spacing: 14) {
                Image(systemName: (session?.isCompleted ?? false) ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)
                Text((session?.isCompleted ?? false) ? "Goal Reached!" : "Run Finished")
                    .font(.largeTitle.bold())
            }

            // Stats
            if let session {
                VStack(spacing: 18) {
                    statRow(title: "Total Distance",
                            value: PaceCalculator.formatKm(session.distanceMeters))
                    statRow(title: "Total Time",
                            value: PaceCalculator.formatTime(session.elapsedTime))
                    statRow(title: "Average Pace",
                            value: PaceCalculator.format(secPerKm: session.averagePaceSecPerKm))
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 20)
            }

            Spacer()

            // Actions
            VStack(spacing: 14) {
                Button {
                    viewModel.saveRun()
                    didSave = true
                } label: {
                    Label(didSave ? "Saved" : "Save Run",
                          systemImage: didSave ? "checkmark" : "square.and.arrow.down")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(didSave)

                Button {
                    viewModel.startNewRun()
                } label: {
                    Label("Start New Run", systemImage: "arrow.clockwise")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
    }
}
