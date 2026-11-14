import AVFoundation
import Combine
import Foundation

/// On-device text-to-speech. Works offline and without any API key.
/// One synthesizer and one queue, so Iris never talks over itself.
@MainActor
final class SpeechOutputService: NSObject, ObservableObject {
    enum Mode {
        /// Stop whatever is being said and say this now.
        case interrupt
        /// Say this after anything already queued.
        case enqueue
    }

    /// Identical text requested again within this window is ignored.
    static let repeatSuppressionInterval: TimeInterval = 3

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var recentUtterances = RecentUtteranceFilter(window: SpeechOutputService.repeatSuppressionInterval)
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        // Share Iris's audio session so speech, the microphone, and the agent stay coordinated.
        synthesizer.usesApplicationAudioSession = true
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

    func speak(_ text: String, mode: Mode = .interrupt) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              recentUtterances.shouldSpeak(trimmed, at: ProcessInfo.processInfo.systemUptime) else { return }
        do {
            try AudioSessionCoordinator.activate()
        } catch {
            // Still try: the synthesizer can fall back to the current route.
        }
        if mode == .interrupt, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        // Respect the user's VoiceOver voice and speaking rate.
        utterance.prefersAssistiveTechnologySettings = true
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        guard synthesizer.isSpeaking || isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Clears repeat suppression, e.g. when the user explicitly asks to hear something again.
    func forgetRecentUtterances() {
        recentUtterances.reset()
    }
}

extension SpeechOutputService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = self.synthesizer.isSpeaking }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = self.synthesizer.isSpeaking }
    }
}

/// Pure repeat-suppression logic, separated for testing.
struct RecentUtteranceFilter {
    let window: TimeInterval
    private var lastSpoken: [String: TimeInterval] = [:]

    init(window: TimeInterval) {
        self.window = window
    }

    mutating func shouldSpeak(_ text: String, at time: TimeInterval) -> Bool {
        lastSpoken = lastSpoken.filter { time - $0.value < window }
        let key = text.lowercased()
        guard lastSpoken[key] == nil else { return false }
        lastSpoken[key] = time
        return true
    }

    mutating func reset() {
        lastSpoken.removeAll()
    }
}
