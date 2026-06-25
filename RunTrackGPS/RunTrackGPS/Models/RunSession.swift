import Foundation
import CoreLocation

/// `CLLocationCoordinate2D` is not `Codable`, so we persist coordinates through
/// this lightweight wrapper.
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The full record of a single run. Used live (during a run) and for persistence
/// of completed runs (see `RunStore`).
struct RunSession: Codable, Identifiable {
    var id: UUID
    var goalDistanceMeters: Double
    var distanceMeters: Double
    var elapsedTime: TimeInterval
    var averagePaceSecPerKm: Double?
    var currentPaceSecPerKm: Double?
    /// Estimated calories burned. Optional so previously-saved runs (without this
    /// field) still decode from `UserDefaults`.
    var caloriesBurned: Double?
    var routeCoordinates: [Coordinate]
    var startTime: Date?
    var endTime: Date?
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        goalDistanceMeters: Double,
        distanceMeters: Double = 0,
        elapsedTime: TimeInterval = 0,
        averagePaceSecPerKm: Double? = nil,
        currentPaceSecPerKm: Double? = nil,
        caloriesBurned: Double? = nil,
        routeCoordinates: [Coordinate] = [],
        startTime: Date? = nil,
        endTime: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.goalDistanceMeters = goalDistanceMeters
        self.distanceMeters = distanceMeters
        self.elapsedTime = elapsedTime
        self.averagePaceSecPerKm = averagePaceSecPerKm
        self.currentPaceSecPerKm = currentPaceSecPerKm
        self.caloriesBurned = caloriesBurned
        self.routeCoordinates = routeCoordinates
        self.startTime = startTime
        self.endTime = endTime
        self.isCompleted = isCompleted
    }

    // MARK: - Derived values

    var goalDistanceKm: Double { goalDistanceMeters / 1000 }
    var distanceKm: Double { distanceMeters / 1000 }

    var remainingMeters: Double {
        max(0, goalDistanceMeters - distanceMeters)
    }

    var remainingKm: Double { remainingMeters / 1000 }

    /// 0...1 progress toward the goal.
    var progressFraction: Double {
        guard goalDistanceMeters > 0 else { return 0 }
        return min(1, distanceMeters / goalDistanceMeters)
    }
}
