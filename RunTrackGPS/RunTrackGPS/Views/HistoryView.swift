import SwiftUI

/// Local history of past runs (distance, time, pace, date). Stored on-device.
struct HistoryView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @Environment(\.dismiss) private var dismiss

    /// Shows a "Done" button to dismiss when presented as a sheet. The History
    /// *tab* sets this to false (there is nothing to dismiss).
    var showsDoneButton = true

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.pastRuns.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            overallStatsCard
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                        if !viewModel.personalRecords.isEmpty {
                            Section {
                                trophiesCard
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                        Section {
                            ForEach(viewModel.pastRuns) { run in
                                NavigationLink(value: run.id) {
                                    row(for: run)
                                }
                            }
                            .onDelete { viewModel.deleteRuns(at: $0) }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: UUID.self) { id in
                        if let run = viewModel.pastRuns.first(where: { $0.id == id }) {
                            RunDetailView(run: run)
                        }
                    }
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Run History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !viewModel.pastRuns.isEmpty {
                        EditButton()
                    }
                }
            }
        }
    }

    // MARK: - Overall stats

    /// Lifetime totals across all saved runs. The average pace here is total time ÷
    /// total distance (Nike Run Club-style), not a mean of per-run paces.
    private var overallStatsCard: some View {
        let stats = viewModel.overallStats
        return VStack(alignment: .leading, spacing: 12) {
            Text("All Time · \(stats.totalRuns) \(stats.totalRuns == 1 ? "run" : "runs")")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.inkSecondary)
            HStack {
                overallStat(value: PaceCalculator.formatKm(stats.totalDistanceMeters),
                            label: "Distance")
                Spacer()
                overallStat(value: PaceCalculator.formatTime(stats.totalTime),
                            label: "Time")
                Spacer()
                overallStat(value: PaceCalculator.format(secPerKm: stats.overallPaceSecPerKm),
                            label: "Avg Pace")
                Spacer()
                overallStat(value: PaceCalculator.formatCalories(stats.totalCalories),
                            label: "Calories")
            }
        }
        .cardStyle()
    }

    private func overallStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - Trophies (personal records)

    /// All-time bests. Each trophy names the run that holds it, so the date
    /// doubles as a reminder of which run to beat. Hidden entirely until there
    /// is at least one qualifying run (see `RunViewModel.PersonalRecords`).
    private var trophiesCard: some View {
        let records = viewModel.personalRecords
        return VStack(alignment: .leading, spacing: 12) {
            Label("Personal Records", systemImage: "trophy.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.inkSecondary)
                .labelStyle(.titleAndIcon)

            if let run = records.longestDistance {
                trophyRow(icon: "arrow.left.and.right",
                          tint: Theme.info,
                          title: "Longest Distance",
                          value: PaceCalculator.formatKm(run.distanceMeters),
                          run: run)
            }
            if let run = records.longestDuration {
                trophyRow(icon: "clock.fill",
                          tint: Theme.accent,
                          title: "Longest Duration",
                          value: PaceCalculator.formatTime(run.elapsedTime),
                          run: run)
            }
            if let run = records.fastestPace {
                trophyRow(icon: "bolt.fill",
                          tint: Theme.success,
                          title: "Fastest Pace",
                          value: PaceCalculator.format(secPerKm: run.averagePaceSecPerKm),
                          run: run)
            }
        }
        .cardStyle()
    }

    private func trophyRow(icon: String,
                           tint: Color,
                           title: String,
                           value: String,
                           run: RunSession) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }

            Spacer(minLength: 8)

            if let date = run.endTime {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Row

    private func row(for run: RunSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(PaceCalculator.formatKm(run.distanceMeters), systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                if run.isFavourite == true {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.warning)
                }
                if run.isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.success)
                }
            }

            HStack(spacing: 18) {
                metric(icon: "clock", text: PaceCalculator.formatTime(run.elapsedTime))
                metric(icon: "speedometer", text: PaceCalculator.format(secPerKm: run.averagePaceSecPerKm))
                metric(icon: "flame", text: PaceCalculator.formatCalories(run.caloriesBurned))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let date = run.endTime {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No runs yet")
                .font(.title3.bold())
            Text("Finish and save a run to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
