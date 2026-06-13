import SwiftUI

/// Local history of past runs (distance, time, pace, date). Stored on-device.
struct HistoryView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.pastRuns.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.pastRuns) { run in
                            row(for: run)
                        }
                        .onDelete { viewModel.deleteRuns(at: $0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Run History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !viewModel.pastRuns.isEmpty {
                        EditButton()
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func row(for run: RunSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(PaceCalculator.formatKm(run.distanceMeters), systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                if run.isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 18) {
                metric(icon: "clock", text: PaceCalculator.formatTime(run.elapsedTime))
                metric(icon: "speedometer", text: PaceCalculator.format(secPerKm: run.averagePaceSecPerKm))
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
