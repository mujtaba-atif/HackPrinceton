import Foundation

enum VoiceGuidanceState: Equatable, Sendable {
    case idle
    case speaking
    case listening
    case unavailable(reason: String)
}

/// Boundary for future speech recognition and spoken guidance services.
@MainActor
protocol VoiceGuidanceProviding: AnyObject {
    var state: VoiceGuidanceState { get }

    func speak(_ phrase: String) async
    func listenForCommand() async throws -> String
    func stop()
}

