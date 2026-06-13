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

    func announceKilometre(_ km: Int) {
        let unit = km == 1 ? "kilometre" : "kilometres"
        speakOnce(key: "km-\(km)", "You have completed \(km) \(unit).")
    }

    func announceHalfway() {
        speakOnce(key: "half", "Halfway completed. Keep going!")
    }

    func announceNinetyPercent() {
        speakOnce(key: "ninety", "90 percent completed. Almost there!")
    }

    func announceGoalReached() {
        speakOnce(key: "goal", "Your goal is reached. Well done!")
    }

    // MARK: - Reset

    /// Clears milestone history for a new run.
    func reset() {
        spokenMilestones.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
    }
}
