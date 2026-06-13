import SwiftUI
import CoreLocation

/// Live running screen: map on top, real-time metrics + controls below.
struct RunView: View {
    @EnvironmentObject private var viewModel: RunViewModel

    var body: some View {
        VStack(spacing: 0) {
            mapSection
            metricsSection
            controls
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Map

    private var mapSection: some View {
        ZStack(alignment: .topTrailing) {
            RouteMapView(
                route: viewModel.location.route,
                currentLocation: viewModel.location.currentLocation?.coordinate,
                followUser: viewModel.followUser
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .trailing, spacing: 10) {
                voiceIndicator
                if viewModel.location.isAccuracyPoor {
                    statusChip(icon: "exclamationmark.triangle.fill",
                               text: "Weak GPS", tint: .orange)
                }
                recenterButton
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    private var voiceIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.voice.isListening ? "mic.fill" : "mic.slash.fill")
                .foregroundStyle(viewModel.voice.isListening ? .green : .secondary)
            Text(viewModel.voice.isListening ? "Listening" : "Voice off")
                .font(.caption.bold())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func statusChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption.bold())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var recenterButton: some View {
        Button {
            viewModel.recenter()
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(spacing: 16) {
            // Goal / progress headline
            VStack(spacing: 6) {
                Text("Goal: \(PaceCalculator.formatKm(viewModel.goalDistanceMeters))")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(PaceCalculator.formatKm(viewModel.distanceMeters))
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())

                ProgressView(value: progress)
                    .tint(.accentColor)

                Text("Remaining: \(PaceCalculator.formatKm(remaining))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stat grid
            HStack {
                stat(title: "Time", value: PaceCalculator.formatTime(viewModel.elapsed))
                Divider()
                stat(title: "Pace (min/km)", value: PaceCalculator.formatShort(secPerKm: viewModel.averagePaceSecPerKm))
            }
        }
        .padding(20)
    }

    private var progress: Double {
        guard viewModel.goalDistanceMeters > 0 else { return 0 }
        return min(1, viewModel.distanceMeters / viewModel.goalDistanceMeters)
    }

    private var remaining: Double {
        max(0, viewModel.goalDistanceMeters - viewModel.distanceMeters)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            if viewModel.isPaused {
                controlButton(title: "Resume", icon: "play.fill", tint: .accentColor) {
                    viewModel.resume()
                }
            } else {
                controlButton(title: "Pause", icon: "pause.fill", tint: .orange) {
                    viewModel.pause()
                }
            }

            controlButton(title: "Stop", icon: "stop.fill", tint: .red) {
                viewModel.stop(completed: false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func controlButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
    }
}
