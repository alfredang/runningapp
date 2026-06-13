// Generates sample run history JSON matching RunSession's Codable format,
// then prints it as hex for `defaults write -data`. For screenshots only.
import Foundation

struct Coordinate: Codable { var latitude: Double; var longitude: Double }
struct RunSession: Codable {
    var id: UUID
    var goalDistanceMeters: Double
    var distanceMeters: Double
    var elapsedTime: TimeInterval
    var averagePaceSecPerKm: Double?
    var currentPaceSecPerKm: Double?
    var routeCoordinates: [Coordinate]
    var startTime: Date?
    var endTime: Date?
    var isCompleted: Bool
}

// Anchor "now" passed in as arg (seconds since 1970) so dates look recent.
let now = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 0
func daysAgo(_ d: Double) -> Date { Date(timeIntervalSince1970: now - d*86400) }

func run(km: Double, goalKm: Double, mins: Double, daysBack: Double, done: Bool) -> RunSession {
    let dist = km * 1000
    let secs = mins * 60
    let pace = secs / km
    return RunSession(id: UUID(), goalDistanceMeters: goalKm*1000, distanceMeters: dist,
                      elapsedTime: secs, averagePaceSecPerKm: pace, currentPaceSecPerKm: pace,
                      routeCoordinates: [], startTime: daysAgo(daysBack),
                      endTime: daysAgo(daysBack).addingTimeInterval(secs), isCompleted: done)
}

let runs = [
    run(km: 10.0, goalKm: 10, mins: 58.5, daysBack: 1,  done: true),
    run(km: 5.2,  goalKm: 5,  mins: 29.7, daysBack: 3,  done: true),
    run(km: 8.4,  goalKm: 10, mins: 50.1, daysBack: 5,  done: false),
    run(km: 20.0, goalKm: 20, mins: 124.0, daysBack: 8, done: true),
    run(km: 5.0,  goalKm: 5,  mins: 31.2, daysBack: 12, done: true),
]

let data = try JSONEncoder().encode(runs)
// Emit as a continuous hex string for `defaults write <domain> <key> -data <hex>`.
print(data.map { String(format: "%02x", $0) }.joined())
