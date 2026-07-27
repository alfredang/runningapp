import Foundation
import Combine
import CoreLocation
import SwiftUI
import UIKit

/// Central MVVM coordinator. Owns the four managers, exposes view state, and turns
/// user/voice actions into manager calls. Views observe this object only.
@MainActor
final class RunViewModel: ObservableObject {

    // MARK: - Managers
    let location = LocationManager()
    let timer = RunTimerManager()
    let feedback = SpeechFeedbackManager()
    let voice = VoiceCommandManager()
    let planner = RoutePlanner()
    private let store = RunStore()
    private let destinationStore = DestinationStore()

    // MARK: - Navigation + goal state
    @Published var screen: AppScreen = .home
    /// Selected goal distance in metres (default 10 km).
    @Published var goalDistanceMeters: Double = 10_000
    @Published var customDistanceText: String = ""

    /// Runner's body weight in kg, used for calorie estimation. Persisted across launches.
    @Published var bodyWeightKg: Double {
        didSet { UserDefaults.standard.set(bodyWeightKg, forKey: Self.weightKey) }
    }
    private static let weightKey = "bodyWeightKg"

    // MARK: - Live run state (mirrors the running session for the views)
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentPaceSecPerKm: Double?
    @Published private(set) var averagePaceSecPerKm: Double?
    @Published private(set) var isPaused = false
    @Published var followUser = true

    // MARK: - Goal completion while still running
    /// True once the goal distance has been reached during the current run. The run
    /// deliberately keeps going — distance, time and pace continue to accumulate.
    @Published private(set) var goalReached = false
    /// Shown briefly over the run screen when the goal is hit and auto-saved.
    @Published var showGoalBanner = false
    /// The id of the auto-saved session for this run, so subsequent auto-saves
    /// update the same history entry instead of appending duplicates.
    private var autoSavedRunID: UUID?
    /// Distance at the last auto-save, used to throttle re-saves past the goal.
    private var lastAutoSaveMeters: Double = 0
    /// How far the runner must travel past the goal before the saved entry is refreshed.
    private static let autoSaveIntervalMeters: Double = 250
    /// Distance run past the goal, in metres.
    var overshootMeters: Double { max(0, distanceMeters - goalDistanceMeters) }

    // MARK: - Favourite destinations
    @Published private(set) var destinations: [Destination] = []
    /// The destination the runner is heading to this run, if any.
    @Published private(set) var selectedDestination: Destination?

    // MARK: - Completed run (for CompletionView)
    @Published private(set) var completedSession: RunSession?

    // MARK: - Errors / alerts
    @Published var activeAlert: RunAlert?

    /// Preset goals shown on the Home screen.
    let presets: [Double] = [5_000, 10_000, 20_000, 40_000]

    private var cancellables = Set<AnyCancellable>()
    private var startDate: Date?
    private var milestoneKm = 0   // highest whole-km already announced

    /// Snapshot used by the map and by persistence.
    private(set) var route: [Coordinate] = []

    /// Saved past runs (most recent first), kept on-device. Published so the Home
    /// and History views update when a run is saved or deleted.
    @Published private(set) var pastRuns: [RunSession] = []

    /// Live calorie estimate for the current run distance.
    var caloriesBurned: Double {
        CalorieCalculator.calories(distanceMeters: distanceMeters, weightKg: bodyWeightKg)
    }

    init() {
        let savedWeight = UserDefaults.standard.double(forKey: Self.weightKey)
        // Use the saved weight only if it's a plausible human value; otherwise default to 56 kg.
        bodyWeightKg = (savedWeight >= 20 && savedWeight <= 300) ? savedWeight : 56
        bind()
        wireVoiceCommands()
        wireSpeechFeedback()
        wireAppLifecycle()
        refreshHistory()
        refreshDestinations()
        #if DEBUG
        applyScreenshotEnvIfNeeded()
        if ProcessInfo.processInfo.environment["VOICE_TEST"] != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.runVoiceSelfTest()
            }
        }
        #endif
    }

    #if DEBUG
    /// Drives the real run + announcement pipeline with injected distances so the
    /// per-kilometre voice reports can be verified on a device without running outside.
    /// Triggered by the `VOICE_TEST` launch env var. Mirrors `startRun()` (including
    /// the live recogniser) so the audio-session behaviour matches a real run.
    func runVoiceSelfTest() {
        goalDistanceMeters = 10_000
        resetForNewRun()
        startDate = Date()
        timer.start()
        voice.startListening()      // reproduce the mic ↔ TTS contention a real run has
        feedback.announceStarted()
        isPaused = false
        screen = .running

        // (distance metres, elapsed seconds) — ~6:00/km pace.
        let steps: [(Double, TimeInterval)] = [
            (1_000, 360), (2_000, 720), (5_000, 1_800), (10_000, 3_600)
        ]
        Task { @MainActor in
            for step in steps {
                try? await Task.sleep(nanoseconds: 13_000_000_000)   // let each report finish
                self.elapsed = step.1
                self.location.simulateDistance(step.0)
            }
        }
    }
    #endif

    /// True when launched in App Store screenshot mode (DEBUG builds only; always
    /// false in Release, so the harness is fully compiled out of shipping builds).
    var isScreenshotMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SCREENSHOT"] != nil
        #else
        return false
        #endif
    }

    // MARK: - Run history

    var mostRecentRun: RunSession? { pastRuns.first }

    private func refreshHistory() {
        pastRuns = store.allRuns()
    }

    func deleteRuns(at offsets: IndexSet) {
        for index in offsets where pastRuns.indices.contains(index) {
            store.delete(pastRuns[index].id)
        }
        refreshHistory()
    }

    func clearHistory() {
        store.clear()
        refreshHistory()
    }

    // MARK: - Favourite destinations

    private func refreshDestinations() {
        destinations = destinationStore.all()
    }

    /// Saves a new favourite (or updates an existing one) and re-plans the route if
    /// the edited destination is the one currently selected.
    func saveDestination(_ destination: Destination) {
        destinationStore.save(destination)
        refreshDestinations()
        if selectedDestination?.id == destination.id {
            selectDestination(destination)
        }
    }

    func deleteDestination(_ id: UUID) {
        destinationStore.delete(id)
        refreshDestinations()
        if selectedDestination?.id == id { clearDestination() }
    }

    /// Creates a favourite at the runner's current position — the common case for
    /// saving "Home" while standing at the front door.
    @discardableResult
    func saveCurrentLocationAsDestination(name: String, symbolName: String) -> Bool {
        guard let coordinate = location.currentLocation?.coordinate else {
            activeAlert = .noLocationFix
            return false
        }
        saveDestination(Destination(name: name,
                                    symbolName: symbolName,
                                    coordinate: Coordinate(coordinate)))
        return true
    }

    /// Chooses a destination and asks MapKit for the shortest walking route to it.
    func selectDestination(_ destination: Destination) {
        selectedDestination = destination
        guard let origin = location.currentLocation?.coordinate else {
            activeAlert = .noLocationFix
            return
        }
        Task { await planner.calculateRoute(from: origin, to: destination) }
    }

    func clearDestination() {
        selectedDestination = nil
        planner.clear()
    }

    /// Recomputes the route to the selected destination from the runner's position.
    func refreshPlannedRoute() {
        guard let destination = selectedDestination,
              let origin = location.currentLocation?.coordinate else { return }
        Task { await planner.calculateRoute(from: origin, to: destination) }
    }

    /// Straight-line distance still to cover to reach the destination, in metres.
    var distanceToDestination: Double? {
        guard let destination = selectedDestination,
              let current = location.currentLocation else { return nil }
        return destination.distance(from: current)
    }

    // MARK: - Goal selection

    func selectPreset(_ meters: Double) {
        goalDistanceMeters = meters
        customDistanceText = ""
    }

    /// Applies a custom goal typed in kilometres. Returns false if the input is invalid.
    @discardableResult
    func applyCustomGoal() -> Bool {
        let normalized = customDistanceText.replacingOccurrences(of: ",", with: ".")
        guard let km = Double(normalized), km > 0, km <= 500 else {
            activeAlert = .invalidGoal
            return false
        }
        goalDistanceMeters = km * 1000
        return true
    }

    var isPresetSelected: Bool { presets.contains(goalDistanceMeters) }

    // MARK: - Permission priming

    func primePermissions() {
        location.requestPermission()
        voice.requestAuthorization { _ in /* surfaced lazily via banners */ }
    }

    // MARK: - Run lifecycle

    func startRun() {
        // Guard: location must be usable.
        guard location.isAuthorized else {
            location.requestPermission()
            activeAlert = .locationDenied
            return
        }

        resetForNewRun()
        startDate = Date()

        location.startTracking()
        timer.start()
        voice.startListening()
        feedback.announceStarted()

        isPaused = false
        screen = .running

        // Re-plan from where the run actually begins, so the guide line on the live
        // map starts at the runner rather than wherever the preview was computed.
        refreshPlannedRoute()
    }

    func pause() {
        guard screen == .running, !isPaused else { return }
        isPaused = true
        timer.pause()
        location.pauseTracking()
        feedback.announcePaused()
    }

    func resume() {
        guard screen == .running, isPaused else { return }
        isPaused = false
        timer.resume()
        location.resumeTracking()
        feedback.announceResumed()
    }

    /// Ends the run and shows the summary. The run counts as completed when the goal
    /// was reached at any point — including runs continued past the goal.
    func stop(completed: Bool = false) {
        guard screen == .running else { return }
        timer.stop()
        location.stopTracking()
        voice.stopListening()

        let didComplete = completed || goalReached
        var session = buildSession(isCompleted: didComplete)

        // Reuse the auto-saved entry's id so finishing updates that history row with
        // the final totals rather than creating a second one for the same run.
        if let existing = autoSavedRunID { session.id = existing }
        completedSession = session

        if didComplete {
            // The goal announcement already played when the goal was crossed.
            store.save(session)
            refreshHistory()
        } else {
            feedback.announceStopped()
        }

        showGoalBanner = false
        screen = .completion
    }

    // MARK: - Completion actions

    func saveRun() {
        guard let session = completedSession else { return }
        store.save(session)
        refreshHistory()
    }

    /// True when this run was already written to history automatically (goal reached),
    /// so the completion screen can show "Saved" instead of a Save button.
    var wasAutoSaved: Bool { autoSavedRunID != nil }

    func startNewRun() {
        completedSession = nil
        resetForNewRun()
        screen = .home
    }

    func recenter() {
        followUser = true
    }

    // MARK: - Private

    private func resetForNewRun() {
        location.reset()
        timer.reset()
        feedback.reset()
        distanceMeters = 0
        elapsed = 0
        currentPaceSecPerKm = nil
        averagePaceSecPerKm = nil
        milestoneKm = 0
        route = []
        followUser = true
        goalReached = false
        showGoalBanner = false
        autoSavedRunID = nil
        lastAutoSaveMeters = 0
    }

    private func bind() {
        // Distance updates drive paces, milestones and goal detection.
        location.$totalDistanceMeters
            .receive(on: RunLoop.main)
            .sink { [weak self] meters in
                self?.handleDistance(meters)
            }
            .store(in: &cancellables)

        // Keep a Codable snapshot of the route for the map + persistence.
        location.$route
            .receive(on: RunLoop.main)
            .sink { [weak self] coords in
                self?.route = coords.map(Coordinate.init)
            }
            .store(in: &cancellables)

        // Timer tick → recompute average pace.
        timer.$elapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.elapsed = value
                self.averagePaceSecPerKm = PaceCalculator.pace(elapsed: value,
                                                               distanceMeters: self.distanceMeters)
            }
            .store(in: &cancellables)
    }

    private func handleDistance(_ meters: Double) {
        guard screen == .running else { return }
        distanceMeters = meters

        // Average pace (over the whole run) and a simple current pace estimate.
        averagePaceSecPerKm = PaceCalculator.pace(elapsed: elapsed, distanceMeters: meters)
        currentPaceSecPerKm = averagePaceSecPerKm   // simple estimate; refined below if moving

        announceMilestonesIfNeeded(meters: meters)

        // Goal reached: auto-save and celebrate, but KEEP RUNNING — distance, time
        // and pace carry on accumulating until the runner stops. Each later distance
        // update refreshes the same saved entry so history reflects the full run.
        if meters >= goalDistanceMeters, goalDistanceMeters > 0 {
            if !goalReached {
                handleGoalReached()
            } else if meters - lastAutoSaveMeters >= Self.autoSaveIntervalMeters {
                // Refresh the saved entry periodically rather than on every GPS fix —
                // a fix arrives roughly every 2 m, and each save re-encodes the whole
                // history array. `stop()` writes the exact final totals regardless.
                autoSaveProgress()
            }
        }
    }

    /// Fires once, the moment the goal distance is crossed.
    private func handleGoalReached() {
        goalReached = true
        feedback.announceGoalReached(goalMeters: goalDistanceMeters,
                                     calories: caloriesBurned)
        autoSaveProgress()

        withAnimation { showGoalBanner = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation { self.showGoalBanner = false }
        }
    }

    /// Writes the in-progress run to history under a stable id, so the result is
    /// never lost even if the app is killed mid-run after the goal.
    private func autoSaveProgress() {
        var session = buildSession(isCompleted: true)
        if let existing = autoSavedRunID {
            session.id = existing
        } else {
            autoSavedRunID = session.id
        }
        store.save(session)
        lastAutoSaveMeters = distanceMeters
        refreshHistory()
    }

    private func announceMilestonesIfNeeded(meters: Double) {
        let fraction = goalDistanceMeters > 0 ? meters / goalDistanceMeters : 0
        let remaining = max(0, goalDistanceMeters - meters)

        // Every completed whole kilometre: full report (distance done, distance left,
        // calories burned, average pace).
        let completedKm = Int(meters / 1000)
        if completedKm > milestoneKm {
            milestoneKm = completedKm
            feedback.announceKilometreReport(
                completedKm: completedKm,
                remainingMeters: remaining,
                calories: CalorieCalculator.calories(distanceMeters: meters, weightKg: bodyWeightKg),
                paceSecPerKm: averagePaceSecPerKm
            )
        }

        // Quarter-goal checkpoints (de-duplicated inside the feedback manager).
        if fraction >= 0.25 { feedback.announcePercent(25, remainingMeters: remaining) }
        if fraction >= 0.50 { feedback.announcePercent(50, remainingMeters: remaining) }
        if fraction >= 0.75 { feedback.announcePercent(75, remainingMeters: remaining) }
    }

    private func buildSession(isCompleted: Bool) -> RunSession {
        RunSession(
            goalDistanceMeters: goalDistanceMeters,
            distanceMeters: distanceMeters,
            elapsedTime: elapsed,
            averagePaceSecPerKm: PaceCalculator.pace(elapsed: elapsed, distanceMeters: distanceMeters),
            currentPaceSecPerKm: currentPaceSecPerKm,
            caloriesBurned: CalorieCalculator.calories(distanceMeters: distanceMeters, weightKg: bodyWeightKg),
            routeCoordinates: route,
            startTime: startDate,
            endTime: Date(),
            isCompleted: isCompleted
        )
    }

    #if DEBUG
    /// Drives the app into a specific screen with mock data for App Store screenshots.
    /// Triggered by the `SCREENSHOT` launch env var (home/running/completion/history).
    private func applyScreenshotEnvIfNeeded() {
        guard let mode = ProcessInfo.processInfo.environment["SCREENSHOT"] else { return }
        // Defer until after the Combine bindings have delivered their initial (zero)
        // values, otherwise those async deliveries would clobber the mock state.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let route = Self.sampleRoute()
            switch mode {
            case "running":
                goalDistanceMeters = 10_000
                elapsed = 2_166                   // 36:06
                distanceMeters = 6_200
                averagePaceSecPerKm = PaceCalculator.pace(elapsed: 2_166, distanceMeters: 6_200)
                currentPaceSecPerKm = averagePaceSecPerKm
                screen = .running
                location.loadMockRoute(route, distanceMeters: 6_200)
            case "beyondgoal":
                // The goal-reached-but-still-running state: banner, "Saved" chip and
                // the "+x km past your goal" readout.
                goalDistanceMeters = 10_000
                elapsed = 3_912                   // 1:05:12
                distanceMeters = 11_420
                averagePaceSecPerKm = PaceCalculator.pace(elapsed: 3_912, distanceMeters: 11_420)
                currentPaceSecPerKm = averagePaceSecPerKm
                goalReached = true
                showGoalBanner = true
                screen = .running
                location.loadMockRoute(route, distanceMeters: 11_420)
            case "completion":
                completedSession = RunSession(
                    goalDistanceMeters: 10_000, distanceMeters: 10_000, elapsedTime: 3_276,
                    averagePaceSecPerKm: 327.6, currentPaceSecPerKm: 327.6,
                    caloriesBurned: CalorieCalculator.calories(distanceMeters: 10_000, weightKg: bodyWeightKg),
                    routeCoordinates: route.map(Coordinate.init), startTime: nil,
                    endTime: Date(timeIntervalSince1970: 1_760_000_000), isCompleted: true)
                screen = .completion
            default:
                break   // "home" / "history" stay on Home (history sheet opened by HomeView)
            }
        }
    }

    /// A short looping route used to render the map polyline in screenshots.
    private static func sampleRoute() -> [CLLocationCoordinate2D] {
        let lat = 1.2820, lon = 103.8636   // Marina Bay loop
        let pts: [(Double, Double)] = [
            (0, 0), (0.0009, 0.0006), (0.0016, 0.0017), (0.0014, 0.0031),
            (0.0004, 0.0038), (-0.0008, 0.0034), (-0.0013, 0.0021), (-0.0009, 0.0008)
        ]
        return pts.map { CLLocationCoordinate2D(latitude: lat + $0.0, longitude: lon + $0.1) }
    }
    #endif

    /// Suspend the voice-command recogniser whenever spoken feedback is playing, so the
    /// synthesizer owns a clean playback session and announcements (per-km report,
    /// percent checkpoints, goal) are always audible — including over Music/YouTube,
    /// which are ducked while speaking and restored afterwards.
    private func wireSpeechFeedback() {
        feedback.onWillSpeak = { [weak self] in self?.voice.suspend() }
        feedback.onDidFinishSpeaking = { [weak self] in self?.voice.resume() }
    }

    /// iOS suspends microphone capture in the background, so keep the recogniser
    /// suspended while backgrounded — otherwise its dead `.playAndRecord` session
    /// contends with the synthesizer and the per-km / goal announcements go silent
    /// when the phone is locked. The location background mode keeps the app running,
    /// and the mixable playback session lets announcements duck Music and play.
    private func wireAppLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.voice.suspend() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.screen == .running, !self.isPaused,
                      !self.feedback.isSpeakingBatch else { return }   // mid-announcement: onDidFinishSpeaking resumes
                self.voice.resume()
            }
            .store(in: &cancellables)
    }

    private func wireVoiceCommands() {
        voice.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .start:
                if self.screen == .home { self.startRun() }
            case .pause:
                self.pause()
            case .resume:
                self.resume()
            case .stop:
                self.stop(completed: false)
            }
        }
    }
}

/// User-facing alerts surfaced by the view model.
enum RunAlert: Identifiable {
    case locationDenied
    case invalidGoal
    case noLocationFix

    var id: Int {
        switch self {
        case .locationDenied: return 0
        case .invalidGoal: return 1
        case .noLocationFix: return 2
        }
    }

    var title: String {
        switch self {
        case .locationDenied: return "Location Needed"
        case .invalidGoal: return "Invalid Distance"
        case .noLocationFix: return "Waiting for GPS"
        }
    }

    var message: String {
        switch self {
        case .locationDenied:
            return "RunTrack GPS needs location access to track your run. Please enable it in Settings."
        case .invalidGoal:
            return "Please enter a distance between 0 and 500 km."
        case .noLocationFix:
            return "Your current location isn't available yet. Step outside for a clear view of the sky and try again."
        }
    }
}
