import Foundation
import MapKit
import Combine

/// Computes the shortest walking/running path from the runner's current location to
/// a saved `Destination` using MapKit's `MKDirections`.
///
/// Walking directions are the right transport type for a runner: they follow
/// footpaths, park connectors, and crossings rather than one-way roads. MapKit
/// returns several candidate routes; we keep the shortest by distance.
@MainActor
final class RoutePlanner: ObservableObject {

    /// The planned path's coordinates, ready to draw as a polyline overlay.
    @Published private(set) var plannedRoute: [CLLocationCoordinate2D] = []
    /// Total distance of the planned route, in metres.
    @Published private(set) var plannedDistanceMeters: Double?
    /// MapKit's expected travel time at walking pace, in seconds.
    @Published private(set) var plannedTravelTime: TimeInterval?
    /// The destination the current plan leads to.
    @Published private(set) var destination: Destination?
    @Published private(set) var isCalculating = false
    /// Set when the last calculation failed (e.g. no route on foot, offline).
    @Published private(set) var errorMessage: String?

    /// True when a usable route is loaded.
    var hasRoute: Bool { !plannedRoute.isEmpty }

    private var currentRequest: MKDirections?
    /// `remainingFromVertex[i]` = route distance from vertex `i` to the end, so the
    /// distance still to run can be read off in O(n) per GPS fix.
    private var remainingFromVertex: [Double] = []

    /// Calculates the shortest walking route from `origin` to `destination`,
    /// replacing any route already loaded.
    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: Destination) async {
        currentRequest?.cancel()
        self.destination = destination
        isCalculating = true
        errorMessage = nil

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.clCoordinate))
        request.transportType = .walking
        request.requestsAlternateRoutes = true

        let directions = MKDirections(request: request)
        currentRequest = directions

        do {
            let response = try await directions.calculate()
            // Superseded by a newer request while in flight — that one owns the state.
            guard directions === currentRequest else { return }
            // "Shortest path" = least distance, not MapKit's default fastest-first order.
            guard let shortest = response.routes.min(by: { $0.distance < $1.distance }) else {
                fail("No walking route found to \(destination.name).")
                return
            }
            plannedRoute = shortest.polyline.coordinates
            remainingFromVertex = Self.suffixDistances(plannedRoute)
            plannedDistanceMeters = shortest.distance
            plannedTravelTime = shortest.expectedTravelTime
            errorMessage = nil
            isCalculating = false
        } catch {
            // A cancelled request is superseded by a newer one — leave that state alone.
            // (Its error used to land after the new request started and overwrite the
            // newer result with "Could not find a route", hiding the planned route.)
            guard directions === currentRequest else { return }
            if (error as NSError).code == MKError.loadingThrottled.rawValue {
                fail("Route lookup was throttled. Please try again.")
            } else if !Task.isCancelled {
                fail("Could not find a route to \(destination.name). Check your connection.")
            } else {
                isCalculating = false
            }
        }
    }

    /// Discards the planned route (e.g. the runner cleared their destination).
    func clear() {
        currentRequest?.cancel()
        currentRequest = nil
        plannedRoute = []
        remainingFromVertex = []
        plannedDistanceMeters = nil
        plannedTravelTime = nil
        destination = nil
        isCalculating = false
        errorMessage = nil
    }

    /// Distance still to run along the planned route from `location`: the gap to the
    /// nearest route vertex plus the route length from that vertex onward. Falls back
    /// to nil when no route is loaded (callers then show the straight-line distance).
    func remainingRouteDistance(from location: CLLocation) -> Double? {
        guard !plannedRoute.isEmpty, remainingFromVertex.count == plannedRoute.count else { return nil }
        var bestIndex = 0
        var bestGap = Double.infinity
        for (i, c) in plannedRoute.enumerated() {
            let gap = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if gap < bestGap { bestGap = gap; bestIndex = i }
        }
        return bestGap + remainingFromVertex[bestIndex]
    }

    private static func suffixDistances(_ coords: [CLLocationCoordinate2D]) -> [Double] {
        guard !coords.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: coords.count)
        for i in stride(from: coords.count - 2, through: 0, by: -1) {
            let a = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
            let b = CLLocation(latitude: coords[i + 1].latitude, longitude: coords[i + 1].longitude)
            result[i] = result[i + 1] + a.distance(from: b)
        }
        return result
    }

    private func fail(_ message: String) {
        plannedRoute = []
        remainingFromVertex = []
        plannedDistanceMeters = nil
        plannedTravelTime = nil
        isCalculating = false
        errorMessage = message
    }
}

extension MKPolyline {
    /// The polyline's points as an array of coordinates.
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
