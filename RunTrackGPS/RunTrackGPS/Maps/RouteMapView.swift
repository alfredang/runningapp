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
    /// Called when the runner pans/zooms the map themselves, so the owner can turn
    /// `followUser` off (and offer a recenter button) instead of snapping back.
    var onUserMovedMap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isRotateEnabled = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onUserMovedMap = onUserMovedMap
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
        /// Signature of the planned route last drawn, so an unchanged plan isn't torn
        /// down and re-added on every location update — while a NEW plan with the same
        /// point count (e.g. a different destination) is still redrawn.
        private var lastPlannedSignature: PlannedSignature?
        private var didFramePlannedRoute = false

        var onUserMovedMap: (() -> Void)?
        /// Set the instant the runner breaks follow mode by panning. SwiftUI only
        /// hears about it asynchronously, so until `followUser` flips to false this
        /// stops `update` from re-engaging follow and yanking the map back.
        private var userBrokeFollow = false
        private var lastFollowUser = true
        /// True while WE change the tracking mode, so that change isn't mistaken for
        /// the runner's gesture.
        private var isSettingTrackingMode = false

        private struct PlannedSignature: Equatable {
            var count: Int
            var firstLat: Double, firstLon: Double
            var lastLat: Double, lastLon: Double

            init(_ coords: [CLLocationCoordinate2D]) {
                count = coords.count
                firstLat = coords.first?.latitude ?? 0
                firstLon = coords.first?.longitude ?? 0
                lastLat = coords.last?.latitude ?? 0
                lastLon = coords.last?.longitude ?? 0
            }
        }

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
            let signature = PlannedSignature(plannedRoute)
            if signature != lastPlannedSignature {
                if let existing = plannedPolyline {
                    mapView.removeOverlay(existing)
                    plannedPolyline = nil
                }
                if plannedRoute.count >= 2 {
                    let line = MKPolyline(coordinates: plannedRoute, count: plannedRoute.count)
                    mapView.addOverlay(line, level: .aboveRoads)
                    plannedPolyline = line
                }
                lastPlannedSignature = signature
                didFramePlannedRoute = false
            }

            // --- Destination pin ---
            // "Back to Start" reuses the existing Start flag rather than a second pin.
            if let destination, !destination.isStartPoint {
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
            //
            // Following uses MapKit's own user-tracking mode instead of calling
            // `setRegion` on every update. The old approach re-centred the camera on
            // every SwiftUI refresh (the 1 Hz timer plus every GPS fix), so any pan was
            // undone within a second and the map felt locked to a small area. Tracking
            // mode is dropped by MapKit the moment the runner pans, which we report via
            // `onUserMovedMap`; the recenter button turns it back on.
            if framesPlannedRoute, let line = plannedPolyline, !didFramePlannedRoute {
                mapView.setVisibleMapRect(
                    line.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                    animated: false)
                didFramePlannedRoute = true
            } else if !framesPlannedRoute {
                if followUser && !lastFollowUser { userBrokeFollow = false }   // recentred
                lastFollowUser = followUser

                if followUser, !userBrokeFollow, let current {
                    if !didCenterOnce {
                        // First fix: a runner-sized zoom, then hand over to tracking.
                        mapView.setRegion(MKCoordinateRegion(center: current,
                                                             latitudinalMeters: 400,
                                                             longitudinalMeters: 400),
                                          animated: false)
                        didCenterOnce = true
                    }
                    if mapView.userTrackingMode == .none {
                        setTrackingMode(.follow, on: mapView, animated: true)
                    }
                } else if !followUser, mapView.userTrackingMode != .none {
                    setTrackingMode(.none, on: mapView, animated: false)
                }
            }
        }

        private func setTrackingMode(_ mode: MKUserTrackingMode, on mapView: MKMapView, animated: Bool) {
            isSettingTrackingMode = true
            mapView.setUserTrackingMode(mode, animated: animated)
            isSettingTrackingMode = false
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            guard mode == .none, !isSettingTrackingMode, lastFollowUser else { return }
            userBrokeFollow = true
            DispatchQueue.main.async { [weak self] in self?.onUserMovedMap?() }
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
