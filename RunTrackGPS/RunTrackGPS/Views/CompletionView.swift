import SwiftUI

/// Post-run summary with Save / Start New Run actions. Runs that reached their goal
/// were already written to history automatically, so the Save button is replaced by
/// a "Saved to History" confirmation.
struct CompletionView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @State private var didSave = false

    private var session: RunSession? { viewModel.completedSession }
    private var goalReached: Bool { session?.isCompleted ?? false }
    private var isAutoSaved: Bool { viewModel.wasAutoSaved }

    /// Distance run beyond the goal, if any.
    private var overshoot: Double {
        guard let session else { return 0 }
        return max(0, session.distanceMeters - session.goalDistanceMeters)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Headline
            VStack(spacing: 14) {
                Image(systemName: goalReached ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.system(size: 72))
                    .foregroundStyle(goalReached ? Theme.success : Theme.accent)
                Text(goalReached ? "Goal Reached!" : "Run Finished")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                if goalReached {
                    Text(overshoot > 10
                         ? "You went \(PaceCalculator.formatKm(overshoot)) past your goal! 🎉"
                         : "Congratulations — you hit your goal! 🎉")
                        .font(.headline)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
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
                    statRow(title: "Calories",
                            value: PaceCalculator.formatCalories(session.caloriesBurned))
                }
                .frame(maxWidth: .infinity)
                .cardStyle(padding: 20, cornerRadius: 20)
                .padding(.horizontal, 20)
            }

            Spacer()

            // Actions
            VStack(spacing: 14) {
                if isAutoSaved {
                    Label("Saved to History", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.success)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Theme.success.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14))
                } else {
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
                    .tint(Theme.accent)
                    .disabled(didSave)
                }

                Button {
                    viewModel.startNewRun()
                } label: {
                    Label("Start New Run", systemImage: "arrow.clockwise")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .canvasBackground()
        .overlay {
            // Balloon celebration — only when the runner met their goal.
            if goalReached {
                CelebrationView()
                    .transition(.opacity)
            }
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
    }
}
