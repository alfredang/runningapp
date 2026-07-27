import SwiftUI
import CoreLocation

/// Live running screen: map on top, real-time metrics + controls below.
///
/// After the goal is reached the run deliberately continues — the headline switches
/// to a "goal reached, keep going" state showing the distance run past the goal, and
/// distance/time/pace keep accumulating until the runner taps Stop.
struct RunView: View {
    @EnvironmentObject private var viewModel: RunViewModel

    var body: some View {
        VStack(spacing: 0) {
            mapSection
            metricsSection
            controls
        }
        .canvasBackground()
    }

    // MARK: - Map

    private var mapSection: some View {
        ZStack(alignment: .topTrailing) {
            RouteMapView(
                route: viewModel.location.route,
                currentLocation: viewModel.location.currentLocation?.coordinate,
                followUser: viewModel.followUser,
                plannedRoute: viewModel.planner.plannedRoute,
                destination: viewModel.selectedDestination
            )
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .trailing, spacing: 10) {
                voiceIndicator
                if viewModel.location.isAccuracyPoor {
                    statusChip(icon: "exclamationmark.triangle.fill",
                               text: "Weak GPS", tint: Theme.warning)
                }
                if let remaining = viewModel.distanceToDestination,
                   let destination = viewModel.selectedDestination {
                    statusChip(icon: destination.symbolName,
                               text: "\(PaceCalculator.formatKm(remaining)) to \(destination.name)",
                               tint: Theme.info)
                }
                recenterButton
            }
            .padding(12)

            // Goal-reached celebration banner, auto-dismissing after a few seconds.
            // Kept clear of the status bar / Dynamic Island by the safe-area inset.
            if viewModel.showGoalBanner {
                goalBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var goalBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal reached! 🎉")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Saved to history — keep running, we're still tracking.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.success, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.success.opacity(0.35), radius: 14, y: 6)
    }

    private var voiceIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.voice.isListening ? "mic.fill" : "mic.slash.fill")
                .foregroundStyle(viewModel.voice.isListening ? Theme.success : Theme.inkSecondary)
            Text(viewModel.voice.isListening ? "Listening" : "Voice off")
                .font(.caption.bold())
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private func statusChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption.bold()).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }

    private var recenterButton: some View {
        Button {
            viewModel.recenter()
        } label: {
            Image(systemName: "location.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(spacing: 16) {
            // Goal / progress headline
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Goal: \(PaceCalculator.formatKm(viewModel.goalDistanceMeters))")
                        .font(.headline)
                        .foregroundStyle(Theme.inkSecondary)
                    if viewModel.goalReached {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.success)
                    }
                }

                Text(PaceCalculator.formatKm(viewModel.distanceMeters))
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(viewModel.goalReached ? Theme.success : Theme.accent)
                    .contentTransition(.numericText())

                ProgressView(value: progress)
                    .tint(viewModel.goalReached ? Theme.success : Theme.accent)

                // Past the goal the "remaining" figure is meaningless — show how far
                // beyond the goal the runner has gone instead.
                if viewModel.goalReached {
                    Text("+\(PaceCalculator.formatKm(viewModel.overshootMeters)) past your goal")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.success)
                } else {
                    Text("Remaining: \(PaceCalculator.formatKm(remaining))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            // Stat grid
            HStack {
                stat(title: "Time", value: PaceCalculator.formatTime(viewModel.elapsed))
                Divider()
                stat(title: "Pace (min/km)", value: PaceCalculator.formatShort(secPerKm: viewModel.averagePaceSecPerKm))
                Divider()
                stat(title: "Calories", value: "\(Int(viewModel.caloriesBurned.rounded()))")
            }
        }
        .padding(20)
        .background(Theme.card)
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
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            if viewModel.isPaused {
                controlButton(title: "Resume", icon: "play.fill", tint: Theme.accent) {
                    viewModel.resume()
                }
            } else {
                controlButton(title: "Pause", icon: "pause.fill", tint: Theme.warning) {
                    viewModel.pause()
                }
            }

            controlButton(title: viewModel.goalReached ? "Finish" : "Stop",
                          icon: "stop.fill", tint: Theme.danger) {
                viewModel.stop()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 24)
        .background(Theme.card)
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
