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

    // MARK: - Tracking lifecycle

    func startTracking() {
        requestAlwaysIfNeeded()
        // `allowsBackgroundLocationUpdates` can only be true once we have authorization.
        if isAuthorized {
            manager.allowsBackgroundLocationUpdates = true
        }
        isTracking = true
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
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
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
#endif
}
