import Foundation

/// Pure calorie math for running. Energy expenditure while running is, to a good
/// approximation, linear in body weight and distance (~1 kcal per kg per km) and
/// largely independent of pace, so we use the well-known coefficient form:
///
///     kcal ≈ weightKg × distanceKm × 1.036
///
/// The 1.036 factor is the standard net-running figure used by most fitness apps.
enum CalorieCalculator {

    /// Coefficient: net kilocalories burned per kilogram of body weight per kilometre run.
    private static let kcalPerKgPerKm = 1.036

    /// Estimated calories burned for a given distance and body weight.
    static func calories(distanceMeters: Double, weightKg: Double) -> Double {
        let km = distanceMeters / 1000
        guard km > 0, weightKg > 0 else { return 0 }
        return km * weightKg * kcalPerKgPerKm
    }
}
