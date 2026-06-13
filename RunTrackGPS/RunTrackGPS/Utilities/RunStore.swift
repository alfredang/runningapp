import Foundation

/// Lightweight persistence of completed runs as JSON in `UserDefaults`.
/// Kept deliberately simple — no Core Data for a lightweight app.
final class RunStore {

    private let defaults: UserDefaults
    private let key = "RunTrackGPS.savedRuns"
    private let maxStored = 50

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// All saved runs, most recent first.
    func allRuns() -> [RunSession] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let runs = (try? JSONDecoder().decode([RunSession].self, from: data)) ?? []
        return runs.sorted { ($0.endTime ?? .distantPast) > ($1.endTime ?? .distantPast) }
    }

    /// The latest saved run, used for the Home screen's "Recent run" card.
    var mostRecent: RunSession? { allRuns().first }

    /// Appends a run and trims history to `maxStored`. Route coordinates are dropped
    /// to keep on-device storage small — history only needs distance/time/pace/date.
    func save(_ session: RunSession) {
        var summary = session
        summary.routeCoordinates = []
        var runs = allRuns()
        runs.removeAll { $0.id == summary.id }   // de-dupe by id
        runs.insert(summary, at: 0)
        persist(Array(runs.prefix(maxStored)))
    }

    /// Removes a saved run by id.
    func delete(_ id: UUID) {
        persist(allRuns().filter { $0.id != id })
    }

    /// Deletes all saved runs.
    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ runs: [RunSession]) {
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: key)
        }
    }
}
