import SwiftUI
import CoreLocation

/// Dashboard: logo + title, preset distance buttons, custom distance input,
/// current goal, Start Run, and a recent-run summary.
struct HomeView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @FocusState private var customFieldFocused: Bool
    @State private var showHistory = false

    private var presetTitles: [(meters: Double, label: String)] {
        [(5_000, "5 KM"), (10_000, "10 KM"), (20_000, "20 KM"), (40_000, "40 KM")]
    }

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                permissionBanner

                presetGrid

                customInput

                goalDisplay

                startButton

                recentRun

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onTapGesture { customFieldFocused = false }
        .onAppear {
            if viewModel.isScreenshotMode {
                if ProcessInfo.processInfo.environment["SCREENSHOT"] == "history" { showHistory = true }
            } else {
                viewModel.primePermissions()
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView().environmentObject(viewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text("RunTrack GPS")
                .font(.largeTitle.bold())
            Text("Track your run. Reach your goal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    // MARK: - Permission banner

    @ViewBuilder
    private var permissionBanner: some View {
        if !viewModel.location.isAuthorized {
            banner(icon: "location.slash.fill",
                   text: "Location access is required to track your run.",
                   tint: .orange)
        } else if !viewModel.location.hasBackgroundAuthorization {
            banner(icon: "moon.fill",
                   text: "Allow \"Always\" location for full background tracking.",
                   tint: .yellow)
        }
    }

    private func banner(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(text).font(.footnote)
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(12)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Preset grid

    private var presetGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(presetTitles, id: \.meters) { preset in
                Button {
                    viewModel.selectPreset(preset.meters)
                    customFieldFocused = false
                } label: {
                    Text(preset.label)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(PresetButtonStyle(
                    isSelected: viewModel.isPresetSelected && viewModel.goalDistanceMeters == preset.meters
                ))
            }
        }
    }

    // MARK: - Custom input

    private var customInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom distance")
                .font(.headline)
            HStack {
                TextField("e.g. 7.5", text: $viewModel.customDistanceText)
                    .keyboardType(.decimalPad)
                    .focused($customFieldFocused)
                    .font(.title3)
                    .padding(.vertical, 12)
                Text("km")
                    .foregroundStyle(.secondary)
                Button("Set") {
                    if viewModel.applyCustomGoal() { customFieldFocused = false }
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Goal display

    private var goalDisplay: some View {
        VStack(spacing: 4) {
            Text("GOAL")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(PaceCalculator.formatKm(viewModel.goalDistanceMeters))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Start button

    private var startButton: some View {
        Button {
            customFieldFocused = false
            viewModel.startRun()
        } label: {
            Label("Start Run", systemImage: "play.fill")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.accentColor)
    }

    // MARK: - Recent run

    @ViewBuilder
    private var recentRun: some View {
        if let run = viewModel.mostRecentRun {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Run")
                        .font(.headline)
                    Spacer()
                    Button {
                        showHistory = true
                    } label: {
                        Label("View All (\(viewModel.pastRuns.count))", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.bold())
                    }
                }
                HStack {
                    summaryItem(title: "Distance", value: PaceCalculator.formatKm(run.distanceMeters))
                    Divider()
                    summaryItem(title: "Time", value: PaceCalculator.formatTime(run.elapsedTime))
                    Divider()
                    summaryItem(title: "Pace", value: PaceCalculator.format(secPerKm: run.averagePaceSecPerKm))
                }
                if let date = run.endTime {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Large, high-contrast preset button styling with a selected state.
private struct PresetButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
