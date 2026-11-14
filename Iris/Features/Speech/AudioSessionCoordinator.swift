import AVFoundation
import Foundation

/// The single place Iris configures `AVAudioSession` for on-device speech and recognition.
/// ARKit's camera session does not use audio, so none of this affects the camera.
///
/// The ElevenLabs agent (LiveKit underneath) manages the session itself while a conversation is
/// active, including echo cancellation so the agent never hears its own voice. Iris never runs
/// on-device speech or recognition during a conversation, so the two never compete.
enum AudioSessionCoordinator {
    /// One category for speaking and listening: spoken audio through the speaker, microphone input.
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
