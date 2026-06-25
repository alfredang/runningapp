import Foundation
import AVFoundation

/// Speaks audio feedback using `AVSpeechSynthesizer`. Milestone announcements are
/// de-duplicated so each one fires at most once per run.
final class SpeechFeedbackManager: NSObject, ObservableObject {

    private let synthesizer = AVSpeechSynthesizer()
    /// Keys of milestone announcements already spoken this run (e.g. "km-1", "half").
    private var spokenMilestones: Set<String> = []

    override init() {
        super.init()
    }

    // MARK: - Audio session

    /// Configures playback so announcements are audible in the background (Audio
    /// background mode) and duck other audio (music) rather than stopping it.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback,
                                 mode: .spokenAudio,
                                 options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: - Core speak

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    /// Speaks once per unique `key` per run.
    private func speakOnce(key: String, _ text: String) {
        guard !spokenMilestones.contains(key) else { return }
        spokenMilestones.insert(key)
        speak(text)
    }

    // MARK: - Lifecycle announcements (always spoken)

    func announceStarted()  { speak("Run started. Good luck!") }
    func announcePaused()   { speak("Run paused.") }
    func announceResumed()  { speak("Run resumed.") }
    func announceStopped()  { speak("Run stopped.") }

    // MARK: - Milestone announcements (de-duplicated)

    /// Full progress report spoken once for each completed whole kilometre:
    /// distance completed, distance remaining, calories burned, and average pace.
    func announceKilometreReport(completedKm: Int,
                                 remainingMeters: Double,
                                 calories: Double,
                                 paceSecPerKm: Double?) {
        let unit = completedKm == 1 ? "kilometre" : "kilometres"
        var parts = ["\(completedKm) \(unit) completed.",
                     "\(spokenDistance(remainingMeters)) to go.",
                     "\(Int(calories.rounded())) calories burned."]
        if let pace = paceSecPerKm, pace.isFinite, pace > 0 {
            parts.append("Average pace \(spokenPace(pace)).")
        }
        speakOnce(key: "km-\(completedKm)", parts.joined(separator: " "))
    }

    /// Spoken checkpoint at a percentage of the goal (25 / 50 / 75 %).
    func announcePercent(_ percent: Int, remainingMeters: Double) {
        speakOnce(key: "pct-\(percent)",
                  "\(percent) percent complete. \(spokenDistance(remainingMeters)) remaining. Keep going!")
    }

    /// Celebratory announcement when the runner meets their goal.
    func announceGoalReached(goalMeters: Double, calories: Double) {
        let msg = "Congratulations! You reached your goal of \(spokenDistance(goalMeters)), "
            + "burning \(Int(calories.rounded())) calories. Well done!"
        speakOnce(key: "goal", msg)
    }

    // MARK: - Spoken formatting helpers

    /// Distance in kilometres, one decimal, voiced naturally (e.g. "2.5 kilometres").
    private func spokenDistance(_ meters: Double) -> String {
        let km = (meters / 1000 * 10).rounded() / 10
        let value = km == km.rounded() ? String(Int(km)) : String(format: "%.1f", km)
        let unit = km == 1 ? "kilometre" : "kilometres"
        return "\(value) \(unit)"
    }

    /// Pace voiced as minutes and seconds per kilometre.
    private func spokenPace(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if seconds == 0 { return "\(minutes) minutes per kilometre" }
        return "\(minutes) minutes \(seconds) seconds per kilometre"
    }

    // MARK: - Reset

    /// Clears milestone history for a new run.
    func reset() {
        spokenMilestones.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
    }
}
