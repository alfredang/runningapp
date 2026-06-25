import SwiftUI
import CoreLocation

/// Dashboard: logo + title, preset distance buttons, custom distance input,
/// current goal, Start Run, and a recent-run summary.
struct HomeView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @FocusState private var customFieldFocused: Bool
    @State private var showHistory = false

    /// Preset goal distances shown in the dropdown.
    private let presetOptions: [(label: String, meters: Double)] = [
        ("1 km", 1_000), ("2 km", 2_000), ("3 km", 3_000), ("5 km", 5_000),
        ("10 km", 10_000), ("15 km", 15_000), ("20 km", 20_000),
        ("Half Marathon (21.1 km)", 21_097.5), ("30 km", 30_000),
        ("Marathon (42.2 km)", 42_195)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                permissionBanner

                distanceDropdown

                weightInput

                startButton

                recentRun

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // The decimal pad has no return key — give it a Done button to dismiss.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { customFieldFocused = false }
            }
        }
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

    // MARK: - Preset distance dropdown

    private var currentDistanceLabel: String {
        presetOptions.first { $0.meters == viewModel.goalDistanceMeters }?.label
            ?? PaceCalculator.formatKm(viewModel.goalDistanceMeters)
    }

    private var distanceDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distance")
                .font(.headline)
            Menu {
                ForEach(presetOptions, id: \.meters) { option in
                    Button {
                        viewModel.selectPreset(option.meters)
                        customFieldFocused = false
                    } label: {
                        if viewModel.goalDistanceMeters == option.meters {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(currentDistanceLabel)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Body weight (for calorie estimation)

    private var weightInput: some View {
        HStack {
            Label("Body weight", systemImage: "scalemass")
                .font(.headline)
            Spacer()
            TextField("56", value: $viewModel.bodyWeightKg, format: .number.grouping(.never))
                .keyboardType(.decimalPad)
                .focused($customFieldFocused)
                .multilineTextAlignment(.trailing)
                .font(.title3)
                .frame(width: 80)
            Text("kg")
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
