import Foundation
import CoreLocation

/// A saved favourite place the runner can route to (e.g. "Home", "Office", "Park").
///
/// Coordinates are stored via the `Coordinate` wrapper so the whole record is
/// `Codable` and can live in `UserDefaults` alongside run history.
struct Destination: Codable, Identifiable, Hashable {
    var id: UUID
    /// Display name chosen by the runner, e.g. "Home".
    var name: String
    /// SF Symbol shown next to the name.
    var symbolName: String
    /// The place itself.
    var coordinate: Coordinate
    /// Human-readable address captured when the destination was saved (may be empty).
    var address: String

    init(id: UUID = UUID(),
         name: String,
         symbolName: String = "house.fill",
         coordinate: Coordinate,
         address: String = "") {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.coordinate = coordinate
        self.address = address
    }

    var clCoordinate: CLLocationCoordinate2D { coordinate.clCoordinate }

    /// Straight-line distance from a location, in metres.
    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude,
                   longitude: coordinate.longitude).distance(from: location)
    }

    /// The SF Symbols offered when creating/editing a destination.
    static let symbolChoices = [
        "house.fill", "building.2.fill", "tree.fill", "figure.run",
        "cup.and.saucer.fill", "heart.fill", "star.fill", "mappin.circle.fill"
    ]
}

/// Persistence for favourite destinations — JSON in `UserDefaults`, matching
/// `RunStore`'s deliberately lightweight approach.
final class DestinationStore {

    private let defaults: UserDefaults
    private let key = "RunTrackGPS.destinations"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [Destination] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Destination].self, from: data)) ?? []
    }

    /// Inserts a new destination, or replaces the existing one with the same id.
    func save(_ destination: Destination) {
        var items = all()
        if let index = items.firstIndex(where: { $0.id == destination.id }) {
            items[index] = destination
        } else {
            items.append(destination)
        }
        persist(items)
    }

    func delete(_ id: UUID) {
        persist(all().filter { $0.id != id })
    }

    private func persist(_ items: [Destination]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
