// Ported from Probe (github.com/amiezeng/Probe), used with the authors' permission.
// Iris changes: lines are always spoken on device. Probe fetched ElevenLabs text-to-speech with an API
// key shipped in the app; Iris never ships a secret key, and the ElevenLabs agent (which needs none)
// is where Iris's AI voice lives.

import AVFoundation
import Combine
import Foundation

/// The app's voice. Everything spoken anywhere goes through here, so there is one voice and one queue:
/// two engines talking at once is two voices over each other.
///
/// `SpeechOutputService` (Turn to Read) and `DistanceBeepController` (Locate) both speak through this,
/// so their lines take turns with the screens' own.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    /// True while a line is coming out of the speaker (published for `SpeechOutputService`'s readers).
    @Published private(set) var isSpeaking = false

    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private let onDevice = AVSpeechSynthesizer()
    private var onDeviceFinished: CheckedContinuation<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        onDevice.delegate = self
        onDevice.usesApplicationAudioSession = true
        // A phone call or Siri stops speech; nothing resumes mid-sentence afterwards.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.stop() }
        }
    }

    func speak(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        queue.append(line)
        guard worker == nil else { return }
        worker = Task {
            while !Task.isCancelled, !queue.isEmpty {
                let next = queue.removeFirst()
                await speakOnDevice(next)
            }
            if !Task.isCancelled { worker = nil }
        }
    }

    /// Anything queued or coming out of the speaker. A caller deciding whether to *add* a line asks this
    /// one: `DistanceBeepController` holds its cues back on it, which keeps the queue one line deep.
    var isBusy: Bool { worker != nil }

    /// Waits for the queue to drain. The timeout matters: screens gate their microphone on this call,
    /// so without it one wedged line would take the whole app's voice control down with it.
    func waitUntilIdle(timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while worker != nil, !Task.isCancelled, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // The one audio session the talking half of the app runs on; `AudioLevels`, `VoiceListener` and the
    // guidance tone ask for this same one rather than their own, so nothing reconfigures the microphone
    // under anything else's tap.
    //
    // .defaultToSpeaker keeps playback on the loudspeaker; recording mode otherwise uses the earpiece.
    // .measurement keeps iOS's own processing off the input — automatic gain control above all — so the
    // water in `WaterVisualizer` is drawn from raw levels.
    //
    // Call this off the main thread: both calls are synchronous IPC to the media server. The category is
    // only set when it isn't already what we want, because every switch costs that again.
    nonisolated static func configureAudioSession() throws {
        let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord || session.mode != .measurement || session.categoryOptions != options {
            try session.setCategory(.playAndRecord, mode: .measurement, options: options)
        }
        try session.setActive(true)
    }

    func stop() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        onDevice.stopSpeaking(at: .immediate)
        finishOnDevice()
        isSpeaking = false
    }

    /// Returns once the line has been spoken, so the queue moves on exactly when the voice stops.
    private func speakOnDevice(_ text: String) async {
        let prepared = await Task.detached(priority: .userInitiated) { () -> Bool in
            (try? Self.configureAudioSession()) != nil
        }.value
        guard !Task.isCancelled else { return }
        if !prepared { print("Speaker: audio session unavailable, speaking anyway") }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 1
        // Respect the user's VoiceOver voice and speaking rate when VoiceOver is on.
        utterance.prefersAssistiveTechnologySettings = true
        // A `didFinish` that never arrives would wedge `worker` non-nil, and the app's voice with it.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(text.count) / 12 + 3))
            guard !Task.isCancelled else { return }
            print("Speaker: on-device speech never reported finishing, moving on")
            self?.finishOnDevice()
        }
        isSpeaking = true
        await withCheckedContinuation { continuation in
            onDeviceFinished = continuation
            onDevice.speak(utterance)
        }
        watchdog.cancel()
        isSpeaking = onDevice.isSpeaking
    }

    private func finishOnDevice() {
        onDeviceFinished?.resume()
        onDeviceFinished = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in finishOnDevice() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in finishOnDevice() }
    }
}
