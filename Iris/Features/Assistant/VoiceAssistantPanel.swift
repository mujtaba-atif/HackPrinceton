import SwiftUI
import UIKit

/// Reusable voice assistant controls: a large microphone, live state, transcript, response,
/// Read Label, Stop Speaking, and permission/error states. Drop it into any screen that owns
/// a `VoiceAssistantCoordinator`.
struct VoiceAssistantPanel: View {
    @ObservedObject var assistant: VoiceAssistantCoordinator
    @Environment(\.openURL) private var openURL
    @State private var showsText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = assistant.errorMessage {
                errorBanner(error)
            }
            conversation
            HStack(alignment: .center, spacing: 16) {
                micButton
                VStack(spacing: 10) {
                    readLabelButton
                    stopButton
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(IrisTheme.surface.opacity(0.97))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(IrisTheme.hairline, lineWidth: 1)
        }
        .foregroundStyle(IrisTheme.primaryText)
        .sheet(isPresented: $showsText) {
            RecognizedTextView(
                state: assistant.ocr.state,
                speech: assistant.speech,
                retry: { assistant.readLabelTapped() },
                askIris: assistant.isConversationActive ? { assistant.askAbout($0) } : nil
            )
        }
        .onChange(of: assistant.ocr.state) { _, state in
            // Show the text when a read finishes and Iris isn't already talking about it.
            if !assistant.isConversationActive, state.result != nil { showsText = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Label(phaseTitle, systemImage: phaseIcon)
                .font(.headline.weight(.bold))
                .foregroundStyle(assistant.phase == .idle ? IrisTheme.primaryText : IrisTheme.accent)
                .accessibilityLabel("Assistant status: \(phaseTitle)")
            Spacer(minLength: 8)
            modeBadge
        }
    }

    @ViewBuilder
    private var modeBadge: some View {
        if assistant.isUsingFallback && !assistant.isConversationActive {
            Text("Basic mode")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(Color.orange.opacity(0.18), in: Capsule())
                .foregroundStyle(Color.orange)
                .accessibilityLabel("Basic mode. Iris's voice service is offline, using simple commands.")
        }
    }

    // MARK: Transcript and response

    @ViewBuilder
    private var conversation: some View {
        let heard = assistant.liveTranscript
        let reply = assistant.liveResponse
        if heard.isEmpty, reply.isEmpty {
            Text(hint)
                .font(.body)
                .foregroundStyle(IrisTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !heard.isEmpty {
                    Text("You: \(heard)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(IrisTheme.secondaryText)
                        .accessibilityLabel("You said: \(heard)")
                }
                if !reply.isEmpty {
                    ScrollView {
                        Text(reply)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .accessibilityLabel("Iris said: \(reply)")
                }
            }
        }
    }

    // MARK: Controls

    private var micButton: some View {
        Button(action: assistant.micTapped) {
            ZStack {
                Circle()
                    .fill(micActive ? IrisTheme.accent : IrisTheme.raisedSurface)
                Circle()
                    .stroke(IrisTheme.accent, lineWidth: micActive ? 0 : 3)
                if assistant.phase == .connecting || assistant.phase == .thinking {
                    ProgressView()
                        .controlSize(.large)
                        .tint(micActive ? .black : IrisTheme.accent)
                } else {
                    Image(systemName: micIcon)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(micActive ? Color.black.opacity(0.88) : IrisTheme.accent)
                }
            }
            .frame(width: 96, height: 96)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(micLabel)
        .accessibilityHint(micHint)
        .accessibilityAddTraits(micActive ? [.isSelected] : [])
    }

    private var readLabelButton: some View {
        Button(action: assistant.readLabelTapped) {
            Label("Read Label", systemImage: "text.viewfinder")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(IrisTheme.accent, in: RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous))
        }
        .disabled(assistant.ocr.state == .reading)
        .accessibilityHint("Reads printed text on the selected object, or in the middle of the camera view")
    }

    private var stopButton: some View {
        Button(action: assistant.stopSpeakingTapped) {
            Label("Stop Speaking", systemImage: "speaker.slash.fill")
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(IrisTheme.raisedSurface, in: RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                        .stroke(IrisTheme.hairline, lineWidth: 1)
                }
        }
        .accessibilityHint(assistant.isConversationActive
                           ? "Interrupts Iris without ending the conversation"
                           : "Stops Iris from speaking")
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            if assistant.canOpenSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.headline.weight(.bold))
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Text

    private var micActive: Bool {
        assistant.isConversationActive || assistant.phase == .listening
    }

    private var phaseTitle: String {
        switch assistant.phase {
        case .idle: assistant.isConversationActive ? "Ready" : "Tap the microphone to talk"
        case .connecting: "Connecting…"
        case .listening: "Listening…"
        case .thinking: "Working on it…"
        case .speaking: "Speaking"
        }
    }

    private var phaseIcon: String {
        switch assistant.phase {
        case .idle: "waveform"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .listening: "ear"
        case .thinking: "ellipsis.circle"
        case .speaking: "speaker.wave.2.fill"
        }
    }

    private var micIcon: String {
        if assistant.isConversationActive { return "phone.down.fill" }
        return assistant.phase == .listening ? "stop.fill" : "mic.fill"
    }

    private var micLabel: String {
        if assistant.isConversationActive { return "End conversation" }
        if assistant.phase == .listening { return "Stop listening" }
        return "Talk to Iris"
    }

    private var micHint: String {
        if assistant.isConversationActive { return "Ends the conversation and turns off the microphone. You can also say goodbye." }
        return "Starts a voice conversation. Ask what's in front of you or to read a label."
    }

    private var hint: String {
        "Ask \"What am I looking at?\", \"Read this label\", or \"Find my water bottle\". Say \"goodbye\" to finish."
    }
}
