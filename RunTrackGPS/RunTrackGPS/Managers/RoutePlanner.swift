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
            // "Shortest path" = least distance, not MapKit's default fastest-first order.
            guard let shortest = response.routes.min(by: { $0.distance < $1.distance }) else {
                fail("No walking route found to \(destination.name).")
                return
            }
            plannedRoute = shortest.polyline.coordinates
            plannedDistanceMeters = shortest.distance
            plannedTravelTime = shortest.expectedTravelTime
            isCalculating = false
        } catch {
            // A cancelled request is superseded by a newer one — leave that state alone.
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
        plannedDistanceMeters = nil
        plannedTravelTime = nil
        destination = nil
        isCalculating = false
        errorMessage = nil
    }

    private func fail(_ message: String) {
        plannedRoute = []
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
