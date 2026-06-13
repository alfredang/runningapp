import SwiftUI
import MapKit

/// Live route map backed by `MKMapView` (wrapped via `UIViewRepresentable`).
///
/// MapKit replaces the Google Maps SDK from the original spec: it is native, free,
/// needs no API key or billing, and still supports polylines, markers, follow-mode,
/// and zoom/pan. See README for how to swap in Google Maps if ever required.
struct RouteMapView: UIViewRepresentable {

    /// The accumulated route coordinates.
    var route: [CLLocationCoordinate2D]
    /// The latest GPS location (drives the "current" marker + follow camera).
    var currentLocation: CLLocationCoordinate2D?
    /// When true, the camera recenters on the user as they move.
    var followUser: Bool

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
                                   followUser: followUser)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {

        private var polyline: MKPolyline?
        private let startAnnotation = MKPointAnnotation()
        private let currentAnnotation = MKPointAnnotation()
        private var didAddStart = false
        private var didCenterOnce = false

        func update(mapView: MKMapView,
                    route: [CLLocationCoordinate2D],
                    current: CLLocationCoordinate2D?,
                    followUser: Bool) {

            // --- Polyline: rebuild from the full route each update ---
            if let existing = polyline {
                mapView.removeOverlay(existing)
            }
            if route.count >= 2 {
                let line = MKPolyline(coordinates: route, count: route.count)
                mapView.addOverlay(line)
                polyline = line
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

                // --- Follow camera ---
                if followUser {
                    let region = MKCoordinateRegion(
                        center: current,
                        latitudinalMeters: 400,
                        longitudinalMeters: 400)
                    mapView.setRegion(region, animated: didCenterOnce)
                    didCenterOnce = true
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = UIColor(named: "AccentColor") ?? .systemBlue
                renderer.lineWidth = 6
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
                view.markerTintColor = .systemIndigo
                view.glyphImage = UIImage(systemName: "flag.fill")
            } else {
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "figure.run")
            }
            return view
        }
    }
}
