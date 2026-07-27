import SwiftUI
import MapKit

/// Live route map backed by `MKMapView` (wrapped via `UIViewRepresentable`).
///
/// MapKit replaces the Google Maps SDK from the original spec: it is native, free,
/// needs no API key or billing, and still supports polylines, markers, follow-mode,
/// and zoom/pan. See README for how to swap in Google Maps if ever required.
///
/// Two overlays are drawn: the **run track** (solid accent line, where you have
/// actually been) and, when a favourite destination is selected, the **planned
/// route** to it (dashed blue line, computed by `RoutePlanner`).
struct RouteMapView: UIViewRepresentable {

    /// The accumulated route coordinates.
    var route: [CLLocationCoordinate2D]
    /// The latest GPS location (drives the "current" marker + follow camera).
    var currentLocation: CLLocationCoordinate2D?
    /// When true, the camera recenters on the user as they move.
    var followUser: Bool
    /// Shortest walking path to the selected destination, if one is planned.
    var plannedRoute: [CLLocationCoordinate2D] = []
    /// The selected destination, shown as a labelled pin.
    var destination: Destination?
    /// When true the camera frames the whole planned route once instead of
    /// following the user — used by the pre-run preview map.
    var framesPlannedRoute = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(mapView: mapView,
                                   route: route,
                                   current: currentLocation,
                                   followUser: followUser,
                                   plannedRoute: plannedRoute,
                                   destination: destination,
                                   framesPlannedRoute: framesPlannedRoute)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {

        private var polyline: MKPolyline?
        private var plannedPolyline: MKPolyline?
        private let startAnnotation = MKPointAnnotation()
        private let currentAnnotation = MKPointAnnotation()
        private let destinationAnnotation = MKPointAnnotation()
        private var didAddStart = false
        private var didCenterOnce = false
        /// Coordinate count of the planned route last drawn, so an unchanged plan
        /// isn't torn down and re-added on every location update.
        private var lastPlannedCount = 0
        private var didFramePlannedRoute = false

        func update(mapView: MKMapView,
                    route: [CLLocationCoordinate2D],
                    current: CLLocationCoordinate2D?,
                    followUser: Bool,
                    plannedRoute: [CLLocationCoordinate2D],
                    destination: Destination?,
                    framesPlannedRoute: Bool) {

            // --- Polyline: rebuild from the full route each update ---
            if let existing = polyline {
                mapView.removeOverlay(existing)
            }
            if route.count >= 2 {
                let line = MKPolyline(coordinates: route, count: route.count)
                mapView.addOverlay(line)
                polyline = line
            }

            // --- Planned route to the destination (only when it changes) ---
            if plannedRoute.count != lastPlannedCount {
                if let existing = plannedPolyline {
                    mapView.removeOverlay(existing)
                    plannedPolyline = nil
                }
                if plannedRoute.count >= 2 {
                    let line = MKPolyline(coordinates: plannedRoute, count: plannedRoute.count)
                    mapView.addOverlay(line, level: .aboveRoads)
                    plannedPolyline = line
                }
                lastPlannedCount = plannedRoute.count
                didFramePlannedRoute = false
            }

            // --- Destination pin ---
            if let destination {
                destinationAnnotation.coordinate = destination.clCoordinate
                destinationAnnotation.title = destination.name
                if !mapView.annotations.contains(where: { $0 === destinationAnnotation }) {
                    mapView.addAnnotation(destinationAnnotation)
                }
            } else if mapView.annotations.contains(where: { $0 === destinationAnnotation }) {
                mapView.removeAnnotation(destinationAnnotation)
            }

            // --- Start marker (first coordinate) ---
            if let first = route.first, !didAddStart {
                startAnnotation.coordinate = first
                startAnnotation.title = "Start"
                mapView.addAnnotation(startAnnotation)
                didAddStart = true
            }

            // --- Current marker ---
            if let current {
                currentAnnotation.coordinate = current
                currentAnnotation.title = "You"
                if !mapView.annotations.contains(where: { $0 === currentAnnotation }) {
                    mapView.addAnnotation(currentAnnotation)
                }
            }

            // --- Camera ---
            // The preview map frames the whole planned route once; the live map
            // follows the runner.
            if framesPlannedRoute, let line = plannedPolyline, !didFramePlannedRoute {
                mapView.setVisibleMapRect(
                    line.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                    animated: false)
                didFramePlannedRoute = true
            } else if !framesPlannedRoute, followUser, let current {
                let region = MKCoordinateRegion(
                    center: current,
                    latitudinalMeters: 400,
                    longitudinalMeters: 400)
                mapView.setRegion(region, animated: didCenterOnce)
                didCenterOnce = true
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                if line === plannedPolyline {
                    // Planned path: dashed, cooler, and drawn thinner so the runner's
                    // own track stays the visually dominant line.
                    renderer.strokeColor = UIColor(Theme.info).withAlphaComponent(0.85)
                    renderer.lineWidth = 5
                    renderer.lineDashPattern = [2, 10]
                } else {
                    renderer.strokeColor = UIColor(Theme.accent)
                    renderer.lineWidth = 6
                }
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Use the default blue dot for the user location.
            if annotation is MKUserLocation { return nil }

            let id = "runMarker"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true

            if annotation === startAnnotation {
                view.markerTintColor = UIColor(Theme.ink)
                view.glyphImage = UIImage(systemName: "flag.fill")
            } else if annotation === destinationAnnotation {
                view.markerTintColor = UIColor(Theme.info)
                view.glyphImage = UIImage(systemName: "mappin.and.ellipse")
            } else {
                view.markerTintColor = UIColor(Theme.accent)
                view.glyphImage = UIImage(systemName: "figure.run")
            }
            return view
        }
    }
}
