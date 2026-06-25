import Foundation

/// Pure pace math + formatting. Pace is stored as seconds-per-kilometre.
enum PaceCalculator {

    /// Average pace over the whole run: `elapsed / distanceKm`.
    /// Returns `nil` when distance is too small to be meaningful.
    static func pace(elapsed: TimeInterval, distanceMeters: Double) -> Double? {
        let km = distanceMeters / 1000
        guard km > 0.01, elapsed > 0 else { return nil }
        return elapsed / km
    }

    /// Formats seconds-per-km as `"6:20 min/km"`. Returns a dash placeholder for nil/invalid input.
    static func format(secPerKm: Double?) -> String {
        guard let secPerKm, secPerKm.isFinite, secPerKm > 0 else {
            return "--:-- min/km"
        }
        let totalSeconds = Int(secPerKm.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d min/km", minutes, seconds)
    }

    /// Short pace form without the unit suffix, e.g. `"6:20"` (unit goes in a label).
    static func formatShort(secPerKm: Double?) -> String {
        guard let secPerKm, secPerKm.isFinite, secPerKm > 0 else { return "--:--" }
        let totalSeconds = Int(secPerKm.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// Formats a distance in metres as kilometres with two decimals, e.g. `"6.20 km"`.
    static func formatKm(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    /// Formats calories as a whole-number `"312 kcal"`. Returns `"0 kcal"` for nil/invalid input.
    static func formatCalories(_ kcal: Double?) -> String {
        guard let kcal, kcal.isFinite, kcal > 0 else { return "0 kcal" }
        return "\(Int(kcal.rounded())) kcal"
    }

    /// Formats a `TimeInterval` as `H:MM:SS` (hours dropped when zero), e.g. `"42:13"`.
    static func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
