import AVFoundation
import Combine
import Foundation

/// Configures the shared audio session for speech, guidance cues, and the microphone. It defers to
/// `Speaker.configureAudioSession` so every part of the app asks for the same one; ARKit's camera uses
/// no audio. The ElevenLabs agent takes the session over during a conversation (see `AgentSession`).
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private(set) var isActive = false

    func activate() {
        do {
            try Speaker.configureAudioSession()
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

/// Text-to-speech with interruption control and duplicate suppression, for features that speak in
/// short instructions (Turn to Read). It speaks through `Speaker.shared`, so there is only ever one
/// voice and one queue in the app.
@MainActor
final class SpeechOutputService: ObservableObject {
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

    private let speaker: Speaker
    private var lastSpokenAt: TimeInterval = -.infinity
    private var subscription: AnyCancellable?

    init(speaker: Speaker? = nil) {
        self.speaker = speaker ?? Speaker.shared
        subscription = self.speaker.$isSpeaking
            .receive(on: RunLoop.main)
            .sink { [weak self] speaking in
                guard let self else { return }
                let busy = speaking || self.speaker.isBusy
                if self.isSpeaking != busy { self.isSpeaking = busy }
            }
    }

    func speak(_ text: String, priority: Priority = .interrupt) {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if phrase == lastSpokenText, speaker.isBusy, now - lastSpokenAt < duplicateWindow { return }

        switch priority {
        case .interrupt:
            if speaker.isBusy { speaker.stop() }
        case .skipIfBusy:
            if speaker.isBusy { return }
        case .enqueue:
            break
        }

        lastSpokenText = phrase
        lastSpokenAt = now
        isSpeaking = true
        speaker.speak(phrase)
    }

    func stop() {
        speaker.stop()
        isSpeaking = false
    }
}
