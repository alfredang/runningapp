import Foundation
import Combine
import CoreLocation

/// Central MVVM coordinator. Owns the four managers, exposes view state, and turns
/// user/voice actions into manager calls. Views observe this object only.
@MainActor
final class RunViewModel: ObservableObject {

    // MARK: - Managers
    let location = LocationManager()
    let timer = RunTimerManager()
    let feedback = SpeechFeedbackManager()
    let voice = VoiceCommandManager()
    private let store = RunStore()

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
        refreshHistory()
        #if DEBUG
        applyScreenshotEnvIfNeeded()
        #endif
    }

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

    /// Stops the run. `completed` is true when the goal was reached.
    func stop(completed: Bool) {
        guard screen == .running else { return }
        timer.stop()
        location.stopTracking()
        voice.stopListening()

        let session = buildSession(isCompleted: completed)
        completedSession = session

        if completed {
            feedback.announceGoalReached(goalMeters: goalDistanceMeters,
                                         calories: session.caloriesBurned ?? 0)
        } else {
            feedback.announceStopped()
        }

        screen = .completion
    }

    // MARK: - Completion actions

    func saveRun() {
        guard let session = completedSession else { return }
        store.save(session)
        refreshHistory()
    }

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

        // Goal reached?
        if meters >= goalDistanceMeters, goalDistanceMeters > 0 {
            stop(completed: true)
        }
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

    var id: Int {
        switch self {
        case .locationDenied: return 0
        case .invalidGoal: return 1
        }
    }

    var title: String {
        switch self {
        case .locationDenied: return "Location Needed"
        case .invalidGoal: return "Invalid Distance"
        }
    }

    var message: String {
        switch self {
        case .locationDenied:
            return "RunTrack GPS needs location access to track your run. Please enable it in Settings."
        case .invalidGoal:
            return "Please enter a distance between 0 and 500 km."
        }
    }
}
