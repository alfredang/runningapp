import SwiftUI

/// Full details of a saved run (opened from History). Nike Run Club-style
/// actions: run it again with the same goal, or star it to save for next time.
struct RunDetailView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    let run: RunSession

    /// Live copy from history, so the star updates in place after a toggle.
    private var currentRun: RunSession {
        viewModel.pastRuns.first(where: { $0.id == run.id }) ?? run
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statsCard
                actions
            }
            .padding(20)
        }
        .canvasBackground()
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.toggleFavourite(currentRun)
                } label: {
                    Image(systemName: currentRun.isFavourite == true ? "star.fill" : "star")
                        .foregroundStyle(Theme.warning)
                }
                .accessibilityLabel(currentRun.isFavourite == true
                                    ? "Remove from saved runs" : "Save for next time")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(PaceCalculator.formatKm(currentRun.distanceMeters))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                if currentRun.isCompleted {
                    Label("Goal reached", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.success)
                }
            }
            if let date = currentRun.endTime {
                Text(date.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        VStack(spacing: 0) {
            statRow(icon: "flag.checkered", label: "Goal",
                    value: PaceCalculator.formatKm(currentRun.goalDistanceMeters))
            divider
            statRow(icon: "clock", label: "Total Time",
                    value: PaceCalculator.formatTime(currentRun.elapsedTime))
            divider
            statRow(icon: "speedometer", label: "Average Pace",
                    value: PaceCalculator.format(secPerKm: currentRun.averagePaceSecPerKm))
            divider
            statRow(icon: "flame", label: "Calories",
                    value: PaceCalculator.formatCalories(currentRun.caloriesBurned))
        }
        .cardStyle(padding: 0)
    }

    private var divider: some View {
        Divider().padding(.leading, 52)
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(.body.bold().monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }

    // MARK: - Actions

    private var actions: some View {
        Button {
            viewModel.runAgain(currentRun)
        } label: {
            Label("Run It Again · \(PaceCalculator.formatKm(currentRun.goalDistanceMeters)) goal",
                  systemImage: "arrow.counterclockwise")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(viewModel.screen == .running)
    }
}
