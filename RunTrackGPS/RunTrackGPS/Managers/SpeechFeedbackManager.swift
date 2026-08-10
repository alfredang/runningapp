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
        // If another app force-claims the audio hardware mid-announcement (the user
        // taps play in YouTube/Music while we're speaking), the synthesizer is left
        // wedged: it keeps accepting utterances but renders silence from then on.
        // Stop it on interruption so the next announcement starts from a clean,
        // freshly activated session instead of inheriting the wedged state.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(audioSessionInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
    }

    // MARK: - Audio session

    /// True while a run owns the audio session (between `beginRunAudioSession()` and
    /// `endRunAudioSession()`).
    private(set) var isRunSessionActive = false

    /// Sets the playback category at launch so the very first announcement on the Home
    /// screen has somewhere to play. During a run the session is owned by
    /// `beginRunAudioSession()` instead.
    func configureAudioSession() {
        applyCoachingCategory()
    }

    /// The one category used throughout: `.playback` keeps audio alive on a locked
    /// screen and in the background (paired with the `audio` background mode), while
    /// `.duckOthers` + `.interruptSpokenAudioAndMixWithOthers` let music/video keep
    /// playing at reduced volume under the coach and pause podcasts outright.
    /// `.mixWithOthers` is deliberately NOT used: it makes the app a passive mixer and
    /// forfeits the right to duck, which is what made announcements inaudible under
    /// YouTube at full volume.
    private func applyCoachingCategory() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    /// Claims the audio session for the WHOLE run and keeps it active until the run
    /// ends — the model every GPS running app uses (Nike Run Club, Strava, Runkeeper).
    ///
    /// This is the core of the background-audio fix. The previous design activated and
    /// deactivated the session around each individual announcement, which failed in two
    /// ways once another app was playing: (1) re-activating an interrupt-capable session
    /// from the background is refused by iOS, so the announcement rendered silence; and
    /// (2) deactivating between announcements handed the route back to YouTube, which
    /// then held it and left the synthesizer wedged. Holding one long-lived session
    /// removes both races — by the time a milestone fires, the session is already ours.
    func beginRunAudioSession() {
        applyCoachingCategory()
        try? AVAudioSession.sharedInstance().setActive(true)
        isRunSessionActive = true
    }

    /// Releases the run's session and tells other apps to un-duck / resume.
    func endRunAudioSession() {
        isRunSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ends the run's session, but waits for any in-flight announcement (e.g. "Run
    /// stopped.") to finish first — deactivating mid-utterance would truncate it.
    func endRunAudioSessionWhenIdle() {
        guard isRunSessionActive else { return }
        if isSpeakingBatch {
            endSessionWhenBatchDrains = true
        } else {
            endRunAudioSession()
        }
    }

    /// Set when the run ends while an announcement is still playing; consumed by
    /// `finishBatchIfDrained()`.
    private var endSessionWhenBatchDrains = false

    /// Restores the coaching category after the recogniser's `.playAndRecord` session
    /// has been torn down, so the next announcement ducks other audio properly.
    func restoreCoachingCategoryAfterMicrophone() {
        applyCoachingCategory()
        if isRunSessionActive { try? AVAudioSession.sharedInstance().setActive(true) }
    }

    /// Ensures the session is live immediately before speaking. During a run this is
    /// normally already true and does nothing; outside a run (Home screen) it activates
    /// on demand. Re-asserting is cheap and covers the case where another app's
    /// interruption deactivated us.
    @discardableResult
    private func ensureSessionActive() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            return true
        } catch {
            // Category may have been clobbered by the recogniser's `.playAndRecord`
            // session; restore ours and retry once.
            applyCoachingCategory()
            return (try? session.setActive(true)) != nil
        }
    }

    // MARK: - Core speak

    /// Settings ▸ "Play over music & videos" is OFF and another app is currently
    /// producing audio: respect the runner's choice and stay quiet. Evaluated per
    /// utterance (not per run) so it tracks media starting mid-run. With the setting
    /// ON — the default — coaching always plays and ducks the other app.
    private var isSuppressedByOtherAudio: Bool {
        !AppSettings.shared.voiceOverOtherAudio
            && AVAudioSession.sharedInstance().isOtherAudioPlaying
    }

    private func speak(_ text: String) {
        guard !isSuppressedByOtherAudio else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        // Coach loudness from Settings (scales our speech only — see AppSettings).
        utterance.volume = Float(AppSettings.shared.coachVolume)

        // Transitioning from idle → speaking: suspend the recogniser (it otherwise
        // holds a `.playAndRecord` session that drowns out the synthesizer) and make
        // sure the session is live. During a run it already is — held since
        // `beginRunAudioSession()` — so this is a no-op and the announcement starts
        // instantly instead of racing YouTube for the route.
        if !isSpeakingBatch {
            isSpeakingBatch = true
            onWillSpeak?()
            ensureSessionActive()
        }
        synthesizer.speak(utterance)
    }

    /// Handles another app force-claiming the hardware (an incoming call, or the user
    /// hitting play in a non-mixable app).
    ///
    /// `.began`: stop the synthesizer so it isn't left wedged rendering silence.
    /// `.ended`: reclaim the session. This is essential during a run — an interruption
    /// deactivates our long-lived session, and without re-activating here every later
    /// milestone would be silent for the rest of the run. That silent-after-a-phone-call
    /// failure is the same class of bug as the original one, so it is handled explicitly.
    @objc private func audioSessionInterrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            if isSpeakingBatch {
                synthesizer.stopSpeaking(at: .immediate)   // → didCancel → finishBatchIfDrained
            }
        case .ended:
            guard isRunSessionActive else { return }
            applyCoachingCategory()
            try? AVAudioSession.sharedInstance().setActive(true)
        @unknown default:
            break
        }
    }

    /// Speaks once per unique `key` per run. A milestone suppressed by the
    /// "play over music" setting is NOT marked as spoken, so it can still be
    /// announced if the runner stops their media before the next milestone —
    /// marking it here would silently burn the announcement forever.
    private func speakOnce(key: String, _ text: String) {
        guard !spokenMilestones.contains(key), !isSuppressedByOtherAudio else { return }
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
        endSessionWhenBatchDrains = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Marks the batch finished and resumes the recogniser once the queue is empty.
    private func finishBatchIfDrained() {
        guard !synthesizer.isSpeaking, isSpeakingBatch else { return }
        isSpeakingBatch = false
        // During a run the session is deliberately KEPT ACTIVE — deactivating here is
        // what previously handed the route back to YouTube and left the next milestone
        // silent. iOS un-ducks the other app on its own once we stop producing audio,
        // so music returns to full volume between announcements anyway. Outside a run
        // there is nothing to hold, so release it and let other apps recover fully.
        if endSessionWhenBatchDrains {
            endSessionWhenBatchDrains = false
            endRunAudioSession()
        } else if !isRunSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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
