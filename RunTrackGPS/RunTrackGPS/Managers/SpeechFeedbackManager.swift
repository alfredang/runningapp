import Foundation
import AVFoundation

/// Speaks audio feedback using `AVSpeechSynthesizer`. Milestone announcements are
/// de-duplicated so each one fires at most once per run.
final class SpeechFeedbackManager: NSObject, ObservableObject {

    private let synthesizer = AVSpeechSynthesizer()
    /// Keys of milestone announcements already spoken this run (e.g. "km-1", "half").
    private var spokenMilestones: Set<String> = []

    /// Called (on the main thread) right before the first utterance of a batch, so
    /// the view model can fully suspend the voice-command recogniser. Without this
    /// the live `.playAndRecord` microphone session steals the route from the
    /// synthesizer and milestone reports (per-km, percent, goal) go unheard.
    var onWillSpeak: (() -> Void)?
    /// Called once the whole utterance queue has drained, so the recogniser resumes.
    var onDidFinishSpeaking: (() -> Void)?

    /// True between `onWillSpeak` and `onDidFinishSpeaking` (queue non-empty).
    private(set) var isSpeakingBatch = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Audio session

    /// Pre-sets the playback category (mixable + ducking) WITHOUT activating it —
    /// activation happens per announcement in `speak()` and is released when the
    /// queue drains, so other audio (Music) is only ducked while actually speaking.
    /// The mixable session is also what lets announcements start while the app is
    /// backgrounded (kept alive by the `location` background mode) with no `audio`
    /// background mode needed.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback,
                                 mode: .spokenAudio,
                                 options: [.duckOthers, .mixWithOthers])
    }

    // MARK: - Core speak

    private func speak(_ text: String) {
        // Transitioning from idle → speaking: suspend the recogniser (synchronously,
        // on the main thread) and claim a clean `.playback` session so the utterance
        // is routed to the speaker. While the recogniser holds `.playAndRecord` the
        // synthesizer is otherwise drowned out — the cause of "only the start message
        // is heard". The session is handed back when the queue drains.
        if !isSpeakingBatch {
            isSpeakingBatch = true
            onWillSpeak?()
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio,
                                     options: [.duckOthers, .mixWithOthers])
            try? session.setActive(true)
        }
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

    /// Marks the batch finished and resumes the recogniser once the queue is empty.
    private func finishBatchIfDrained() {
        guard !synthesizer.isSpeaking, isSpeakingBatch else { return }
        isSpeakingBatch = false
        // Release the ducking session so other audio (Music, Spotify) returns to full
        // volume between announcements. `.notifyOthersOnDeactivation` tells the other
        // app to un-duck. The recogniser (foreground only) reactivates its own session
        // in `onDidFinishSpeaking`; the next announcement reactivates ours.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onDidFinishSpeaking?()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechFeedbackManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Only resume the recogniser once the whole queue has drained, so back-to-back
        // utterances (e.g. km report + percent checkpoint) aren't interrupted.
        finishBatchIfDrained()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishBatchIfDrained()
    }
}
