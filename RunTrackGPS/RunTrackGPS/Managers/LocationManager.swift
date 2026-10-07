import Foundation
import CoreLocation
import Combine

/// Wraps CoreLocation: requests permission, filters noisy GPS fixes, accumulates
/// distance, and publishes the route for the map + view model to observe.
///
/// Distance is accumulated using `currentLocation.distance(from: previousLocation)`
/// over fixes that survive the filtering rules below.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published state
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var totalDistanceMeters: Double = 0
    /// True when the most recent fix had poor horizontal accuracy.
    @Published private(set) var isAccuracyPoor: Bool = false

    // MARK: - Filtering thresholds
    private let maxAcceptableAccuracy: CLLocationAccuracy = 20    // metres
    private let maxFixAge: TimeInterval = 5                       // seconds
    private let maxRealisticSpeed: CLLocationSpeed = 12           // m/s (~43 km/h, faster than any runner)
    private let minMoveDistance: CLLocationDistance = 2           // metres (ignore jitter while standing)

    private let manager = CLLocationManager()
    private var lastAcceptedLocation: CLLocation?
    private var isTracking = false
    /// True while CoreLocation is delivering fixes (either a run or the Home preview).
    private var isUpdating = false
    /// True while the Home screen wants a live position (no distance accumulation).
    private var wantsPreview = false

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Permissions

    /// Requests "When In Use" first; we escalate to "Always" the first time tracking starts.
    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestAlwaysIfNeeded() {
        if authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var hasBackgroundAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    // MARK: - Home preview (position only)

    /// Keeps `currentLocation` fresh on the Home screen, so a destination route — and
    /// its distance — can be planned BEFORE the run starts. Previously CoreLocation was
    /// only started by `startTracking()`, so on Home `currentLocation` was nil and
    /// picking a destination showed no route at all. Foreground-only: background
    /// updates stay off until a run begins.
    func startPreviewUpdates() {
        wantsPreview = true
        guard isAuthorized, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    /// Stops the Home preview (e.g. app backgrounded). Never stops an active run.
    func stopPreviewUpdates() {
        wantsPreview = false
        guard isUpdating, !isTracking, !manager.allowsBackgroundLocationUpdates else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    // MARK: - Tracking lifecycle

    func startTracking() {
        requestAlwaysIfNeeded()
        // `allowsBackgroundLocationUpdates` can only be true once we have authorization.
        if isAuthorized {
            manager.allowsBackgroundLocationUpdates = true
        }
        isTracking = true
        isUpdating = true
        manager.startUpdatingLocation()
    }

    /// Stops feeding new fixes into the distance total without discarding the route.
    func pauseTracking() {
        isTracking = false
        lastAcceptedLocation = nil   // avoid a huge jump segment across the pause gap
    }

    func resumeTracking() {
        isTracking = true
    }

    func stopTracking() {
        isTracking = false
        manager.allowsBackgroundLocationUpdates = false
        // Back on Home the preview keeps the position live for the next route plan.
        if !wantsPreview {
            isUpdating = false
            manager.stopUpdatingLocation()
        }
    }

    /// Clears all accumulated data for a fresh run.
    func reset() {
        route.removeAll()
        totalDistanceMeters = 0
        lastAcceptedLocation = nil
        isAccuracyPoor = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isTracking, isAuthorized {
            manager.allowsBackgroundLocationUpdates = true
        }
        // Permission was granted after Home asked for a preview — start it now.
        if wantsPreview, isAuthorized, !isUpdating {
            isUpdating = true
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        // Always surface the latest fix to the map, even if we reject it for distance.
        currentLocation = newLocation

        // --- Filtering rules ---

        // 1) Reject poor / invalid accuracy.
        guard newLocation.horizontalAccuracy >= 0,
              newLocation.horizontalAccuracy <= maxAcceptableAccuracy else {
            isAccuracyPoor = true
            return
        }
        isAccuracyPoor = false

        // 2) Reject stale fixes.
        guard abs(newLocation.timestamp.timeIntervalSinceNow) <= maxFixAge else { return }

        // Only accumulate distance while actively tracking (not paused).
        guard isTracking else { return }

        guard let last = lastAcceptedLocation else {
            // First accepted fix — seed the route and reference point.
            lastAcceptedLocation = newLocation
            appendCoordinate(newLocation.coordinate)
            return
        }

        let segment = newLocation.distance(from: last)
        let interval = newLocation.timestamp.timeIntervalSince(last.timestamp)

        // 3) Reject unrealistic jumps (teleport-like speed).
        if interval > 0, (segment / interval) > maxRealisticSpeed {
            return
        }

        // 4) Reject near-duplicates / jitter while standing still.
        guard segment >= minMoveDistance else { return }

        totalDistanceMeters += segment
        lastAcceptedLocation = newLocation
        appendCoordinate(newLocation.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure (e.g. momentary GPS loss) is non-fatal; we keep the last state.
        if let clError = error as? CLError, clError.code == .denied {
            stopTracking()
        }
    }

    private func appendCoordinate(_ coordinate: CLLocationCoordinate2D) {
        route.append(coordinate)
    }

#if DEBUG
    /// Injects a fixed route/location for App Store screenshots (DEBUG builds only).
    func loadMockRoute(_ coords: [CLLocationCoordinate2D], distanceMeters: Double) {
        route = coords
        totalDistanceMeters = distanceMeters
        if let last = coords.last {
            currentLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        }
    }

    /// Sets the accumulated distance directly, driving the same `$totalDistanceMeters`
    /// pipeline a real GPS update would (used by the voice self-test).
    func simulateDistance(_ meters: Double) {
        totalDistanceMeters = meters
    }
#endif
}
