import AVFoundation
import Combine
import Foundation
import Speech

enum VoiceListeningState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening(partial: String)
    case unavailable(reason: String, canOpenSettings: Bool)
    case failed(message: String)

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// On-device speech recognition for single spoken commands. Works without any API key.
/// The microphone is only open while `listen()` is running and is always torn down afterwards.
@MainActor
final class VoiceCommandService: ObservableObject {
    /// Stop after this much silence following speech.
    static let silenceTimeout: TimeInterval = 1.5
    /// Hard cap on one listening turn.
    static let maximumDuration: TimeInterval = 10
    /// Give up if the user says nothing at all.
    static let initialSilenceTimeout: TimeInterval = 5

    @Published private(set) var state: VoiceListeningState = .idle

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String?, Never>?
    private var latestTranscript = ""
    private var silenceTimer: Task<Void, Never>?
    private var maximumTimer: Task<Void, Never>?

    /// Listens for one utterance. Returns the final transcript, or nil on silence, cancel, or error.
    func listen() async -> String? {
        guard continuation == nil else { return nil }
        guard await ensurePermissions() else { return nil }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable(reason: "Speech recognition isn't available right now. Check your connection or try again shortly.",
                                 canOpenSettings: false)
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            do {
                try startRecognition(with: recognizer)
            } catch {
                finish(with: nil, failure: "Couldn't start the microphone. " + error.localizedDescription)
            }
        }
    }

    /// Stops listening immediately and returns whatever was heard so far.
    func stop() {
        finish(with: latestTranscript.isEmpty ? nil : latestTranscript)
    }

    func cancel() {
        finish(with: nil)
    }

    // MARK: - Permissions

    private func ensurePermissions() async -> Bool {
        var speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            state = .requestingPermission
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        switch speechStatus {
        case .authorized: break
        case .restricted:
            state = .unavailable(reason: "Speech recognition is restricted on this device.", canOpenSettings: false)
            return false
        default:
            state = .unavailable(reason: "Speech recognition is off. Allow it in Settings to use voice commands.",
                                 canOpenSettings: true)
            return false
        }

        var micGranted = AVAudioApplication.shared.recordPermission == .granted
        if AVAudioApplication.shared.recordPermission == .undetermined {
            state = .requestingPermission
            micGranted = await AVAudioApplication.requestRecordPermission()
        }
        guard micGranted else {
            state = .unavailable(reason: "Microphone access is off. Allow it in Settings to use voice commands.",
                                 canOpenSettings: true)
            return false
        }
        return true
    }

    // MARK: - Recognition

    private func startRecognition(with recognizer: SFSpeechRecognizer) throws {
        AudioSessionCoordinator.shared.activateForListening()
        latestTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Iris.Voice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        state = .listening(partial: "")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error.map(Self.describe)
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.latestTranscript = text
                    self.state = .listening(partial: text)
                    self.restartSilenceTimer(after: Self.silenceTimeout)
                }
                if isFinal {
                    self.finish(with: self.latestTranscript.isEmpty ? nil : self.latestTranscript)
                } else if let failure {
                    // "No speech detected" is a normal outcome, not an error worth showing.
                    if self.latestTranscript.isEmpty, failure.isNoSpeech {
                        self.finish(with: nil)
                    } else if self.latestTranscript.isEmpty {
                        self.finish(with: nil, failure: failure.message)
                    } else {
                        self.finish(with: self.latestTranscript)
                    }
                }
            }
        }

        restartSilenceTimer(after: Self.initialSilenceTimeout)
        maximumTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumDuration))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func restartSilenceTimer(after interval: TimeInterval) {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func finish(with transcript: String?, failure: String? = nil) {
        silenceTimer?.cancel()
        maximumTimer?.cancel()
        silenceTimer = nil
        maximumTimer = nil

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        if let failure {
            state = .failed(message: failure)
        } else if case .listening = state {
            state = .idle
        } else if state == .requestingPermission {
            state = .idle
        }

        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: transcript)
    }

    private struct Failure {
        let message: String
        let isNoSpeech: Bool
    }

    nonisolated private static func describe(_ error: Error) -> Failure {
        let nsError = error as NSError
        // kAFAssistantErrorDomain 1110 = no speech detected; 216/301 = request cancelled.
        let silentCodes: Set<Int> = [1110, 216, 301, 203]
        let isNoSpeech = silentCodes.contains(nsError.code)
        return Failure(message: "Speech recognition failed. Please try again.", isNoSpeech: isNoSpeech)
    }
}
