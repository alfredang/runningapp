import SwiftUI
import CoreLocation

/// Dashboard: logo + title, preset distance buttons, destination picker with route
/// preview, custom distance input, current goal, Start Run, and a recent-run summary.
struct HomeView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @FocusState private var customFieldFocused: Bool
    @State private var showHistory = false
    @State private var showDestinations = false

    /// Preset goal distances shown in the dropdown.
    private let presetOptions: [(label: String, meters: Double)] = [
        ("1 km", 1_000), ("2 km", 2_000), ("3 km", 3_000), ("5 km", 5_000),
        ("10 km", 10_000), ("15 km", 15_000), ("20 km", 20_000),
        ("Half Marathon (21.1 km)", 21_097.5), ("30 km", 30_000),
        ("Marathon (42.2 km)", 42_195)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                permissionBanner

                distanceDropdown

                destinationSection

                weightInput

                startButton

                recentRun

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .canvasBackground()
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
        .sheet(isPresented: $showDestinations) {
            DestinationsView().environmentObject(viewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)
            Text("RunTrack GPS")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
            Text("Track your run. Reach your goal.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.top, 16)
    }

    // MARK: - Permission banner

    @ViewBuilder
    private var permissionBanner: some View {
        if !viewModel.location.isAuthorized {
            banner(icon: "location.slash.fill",
                   text: "Location access is required to track your run.",
                   tint: Theme.danger)
        } else if !viewModel.location.hasBackgroundAuthorization {
            banner(icon: "moon.fill",
                   text: "Allow \"Always\" location for full background tracking.",
                   tint: Theme.warning)
        }
    }

    private func banner(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.footnote).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundStyle(Theme.ink)
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
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: Theme.shadow, radius: 8, y: 3)
            }
        }
    }

    // MARK: - Destination + route preview

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Destination")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    showDestinations = true
                } label: {
                    Label(viewModel.destinations.isEmpty ? "Add" : "Manage",
                          systemImage: viewModel.destinations.isEmpty ? "plus" : "slider.horizontal.3")
                        .font(.subheadline.bold())
                }
                .tint(Theme.accent)
            }

            if let destination = viewModel.selectedDestination {
                selectedDestinationCard(destination)
            } else {
                destinationPicker
            }
        }
    }

    private var destinationPicker: some View {
        Group {
            if viewModel.destinations.isEmpty {
                Button {
                    showDestinations = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(Theme.info)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save a favourite place")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.ink)
                            Text("Get the shortest running route to it")
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .cardStyle(padding: 14)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(viewModel.destinations) { destination in
                        Button {
                            viewModel.selectDestination(destination)
                        } label: {
                            Label(destination.name, systemImage: destination.symbolName)
                        }
                    }
                } label: {
                    HStack {
                        Text("Choose a destination (optional)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Theme.shadow, radius: 8, y: 3)
                }
            }
        }
    }

    private func selectedDestinationCard(_ destination: Destination) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: destination.symbolName)
                    .font(.title3)
                    .foregroundStyle(Theme.info)
                    .frame(width: 42, height: 42)
                    .background(Theme.info.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    routeSummary
                }

                Spacer()

                Button {
                    viewModel.clearDestination()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            // Route preview map — only once MapKit has returned a path.
            if viewModel.planner.hasRoute {
                RouteMapView(route: [],
                             currentLocation: viewModel.location.currentLocation?.coordinate,
                             followUser: false,
                             plannedRoute: viewModel.planner.plannedRoute,
                             destination: destination,
                             framesPlannedRoute: true)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius,
                                                    style: .continuous))
        .shadow(color: Theme.shadow, radius: 10, y: 4)
    }

    @ViewBuilder
    private var routeSummary: some View {
        if viewModel.planner.isCalculating {
            Text("Finding the shortest route…")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        } else if let message = viewModel.planner.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.danger)
        } else if let meters = viewModel.planner.plannedDistanceMeters {
            HStack(spacing: 8) {
                Text(PaceCalculator.formatKm(meters))
                if let time = viewModel.planner.plannedTravelTime {
                    Text("·")
                    Text("~\(Int((time / 60).rounded())) min")
                }
            }
            .font(.caption.bold())
            .foregroundStyle(Theme.info)
        }
    }

    // MARK: - Body weight (for calorie estimation)

    private var weightInput: some View {
        HStack {
            Label("Body weight", systemImage: "scalemass")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer()
            TextField("56", value: $viewModel.bodyWeightKg, format: .number.grouping(.never))
                .keyboardType(.decimalPad)
                .focused($customFieldFocused)
                .multilineTextAlignment(.trailing)
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 80)
            Text("kg")
                .foregroundStyle(Theme.inkSecondary)
        }
        .cardStyle(padding: 14, cornerRadius: 14)
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
        .tint(Theme.accent)
        .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 5)
    }

    // MARK: - Recent run

    @ViewBuilder
    private var recentRun: some View {
        if let run = viewModel.mostRecentRun {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Run")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        showHistory = true
                    } label: {
                        Label("View All (\(viewModel.pastRuns.count))", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.bold())
                    }
                    .tint(Theme.accent)
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
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).foregroundStyle(Theme.ink)
            Text(title).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
