import AVFoundation
import Combine
import Foundation

/// Single owner of the app's audio session. Speech, guidance cues, and the microphone all configure
/// audio through here so they don't overwrite each other's settings. ARKit's camera uses no audio.
/// The ElevenLabs agent manages the session itself (with echo cancellation) during a conversation.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private(set) var isActive = false

    /// One configuration for both speaking and listening, so switching never interrupts speech:
    /// spoken audio through the speaker, playing even with the silent switch on, ducking other audio.
    func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playAndRecord || session.mode != .spokenAudio {
                try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                        options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
            }
            try session.setActive(true)
            isActive = true
        } catch {
            // Speech still plays through the default session if configuration fails.
            isActive = false
        }
    }

    func activateForSpeech() { activate() }
    func activateForListening() { activate() }

    func deactivate() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }
}

/// Reusable text-to-speech with interruption control and duplicate suppression.
/// Uses the person's VoiceOver voice and rate when VoiceOver is on.
@MainActor
final class SpeechOutputService: NSObject, ObservableObject {
    enum Priority {
        /// Cut off anything playing and speak now. Use for instructions and results.
        case interrupt
        /// Play after current speech finishes.
        case enqueue
        /// Drop this phrase if something is already playing. Use for encouragement.
        case skipIfBusy
    }

    @Published private(set) var isSpeaking = false
    private(set) var lastSpokenText: String?

    /// Identical text spoken again within this window, while still speaking, is ignored.
    var duplicateWindow: TimeInterval = 1.5

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAt: TimeInterval = -.infinity

    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        // A phone call or Siri stops speech; nothing resumes mid-sentence afterwards.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.stop() }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func speak(_ text: String, priority: Priority = .interrupt) {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if phrase == lastSpokenText, synthesizer.isSpeaking, now - lastSpokenAt < duplicateWindow { return }

        switch priority {
        case .interrupt:
            if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        case .skipIfBusy:
            if synthesizer.isSpeaking { return }
        case .enqueue:
            break
        }

        AudioSessionCoordinator.shared.activateForSpeech()
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.prefersAssistiveTechnologySettings = true
        lastSpokenText = phrase
        lastSpokenAt = now
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    private func refreshSpeakingState() {
        isSpeaking = synthesizer.isSpeaking
    }
}

extension SpeechOutputService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.refreshSpeakingState() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.refreshSpeakingState() }
    }
}
