import Foundation
import Combine

/// Tracks elapsed running time. Truth comes from wall-clock dates (so background
/// suspension or dropped timer ticks never lose time); a 1 Hz timer only nudges
/// the UI to re-read `elapsed`.
final class RunTimerManager: ObservableObject {

    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var ticker: AnyCancellable?

    /// Computes elapsed time from accumulated segments plus the live segment.
    private func computeElapsed() -> TimeInterval {
        if let segmentStart {
            return accumulated + Date().timeIntervalSince(segmentStart)
        }
        return accumulated
    }

    func start() {
        reset()
        segmentStart = Date()
        isRunning = true
        startTicker()
    }

    func pause() {
        guard isRunning else { return }
        accumulated = computeElapsed()
        segmentStart = nil
        isRunning = false
        elapsed = accumulated
        stopTicker()
    }

    func resume() {
        guard !isRunning else { return }
        segmentStart = Date()
        isRunning = true
        startTicker()
    }

    func stop() {
        accumulated = computeElapsed()
        segmentStart = nil
        isRunning = false
        elapsed = accumulated
        stopTicker()
    }

    func reset() {
        accumulated = 0
        segmentStart = nil
        isRunning = false
        elapsed = 0
        stopTicker()
    }

    private func startTicker() {
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsed = self.computeElapsed()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
