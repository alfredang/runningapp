import Foundation
import Speech
import AVFoundation

/// Recognized voice commands.
enum VoiceCommand: String {
    case start
    case pause
    case resume
    case stop
}

/// Continuous on-device speech recognition that maps spoken keywords to
/// `VoiceCommand`s. Voice *commands* are a foreground feature — mic capture is
/// suspended in the background (voice *feedback* still works there).
final class VoiceCommandManager: NSObject, ObservableObject {

    // MARK: - Published state (drives the RunView indicator)
    @Published private(set) var isListening = false
    @Published private(set) var lastCommandText = ""
    @Published private(set) var authorizationDenied = false

    /// Invoked on the main queue when a command is detected.
    var onCommand: ((VoiceCommand) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Debounce: ignore the same command if fired within this window.
    private let debounceInterval: TimeInterval = 2
    private var lastCommand: VoiceCommand?
    private var lastCommandTime: Date?

    // MARK: - Permissions

    /// Requests speech-recognition + microphone permission. `completion` reports
    /// whether both were granted.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            let speechOK = speechStatus == .authorized
            Self.requestMicrophonePermission { micOK in
                DispatchQueue.main.async {
                    let granted = speechOK && micOK
                    self?.authorizationDenied = !granted
                    completion(granted)
                }
            }
        }
    }

    /// Microphone permission, using the iOS 17+ API where available and falling
    /// back to the deprecated `AVAudioSession` API on iOS 16.
    private static func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }

    var isAvailable: Bool {
        (recognizer?.isAvailable ?? false) && !authorizationDenied
    }

    // MARK: - Listening lifecycle

    func startListening() {
        guard !isListening, isAvailable else { return }
        do {
            try beginRecognition()
            isListening = true
        } catch {
            isListening = false
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }

    private func beginRecognition() throws {
        // Tear down any prior task.
        task?.cancel()
        task = nil

        // `.playAndRecord` lets recognition coexist with spoken feedback (which ducks others).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) { request.requiresOnDeviceRecognition = false }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let phrase = result.bestTranscription.formattedString
                self.handleTranscription(phrase)
                // Restart periodically so the recognizer buffer doesn't grow unbounded.
                if result.isFinal {
                    self.restart()
                }
            }
            if error != nil {
                self.restart()
            }
        }
    }

    /// Restarts the engine (recognizer sessions are time-limited).
    private func restart() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isListening else { return }
            try? self.beginRecognition()
        }
    }

    // MARK: - Keyword parsing

    private func handleTranscription(_ phrase: String) {
        let text = phrase.lowercased()
        DispatchQueue.main.async { self.lastCommandText = phrase }

        // Order matters: check resume/pause/stop before the generic "start".
        let command: VoiceCommand?
        if text.contains("resume") {
            command = .resume
        } else if text.contains("pause") {
            command = .pause
        } else if text.contains("stop") || text.contains("finish") {
            command = .stop
        } else if text.contains("start") || text.contains("begin") {
            command = .start
        } else {
            command = nil
        }

        guard let command else { return }
        fire(command)
    }

    private func fire(_ command: VoiceCommand) {
        let now = Date()
        if command == lastCommand,
           let last = lastCommandTime,
           now.timeIntervalSince(last) < debounceInterval {
            return   // debounce repeats of the same command
        }
        lastCommand = command
        lastCommandTime = now
        DispatchQueue.main.async { self.onCommand?(command) }
    }
}
