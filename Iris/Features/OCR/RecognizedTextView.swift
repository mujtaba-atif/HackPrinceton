import SwiftUI
import UIKit

/// Accessible view of recognized text with read-aloud controls.
struct RecognizedTextView: View {
    let state: OCRState
    @ObservedObject var speech: SpeechOutputService
    var retry: (() -> Void)?
    /// When a conversation is active, sends the text to Iris to explain.
    var askIris: ((OCRResult) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(IrisTheme.screenPadding)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .irisScreenBackground()
            .navigationTitle("Recognized Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        speech.stop()
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
        .tint(IrisTheme.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case let .result(result):
            if let focus = result.focusName {
                Label("Read from the selected \(focus)", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IrisTheme.secondaryText)
            }
            if result.isLowConfidence {
                Label("Some text may be misread. Hold the label steady and try again to confirm.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IrisTheme.primaryText)
                    .textSelection(.enabled)
            }
            if AssistantFacts.needsSafetyNote(result.text) {
                Text(AssistantFacts.safetyNote)
                    .font(.footnote)
                    .foregroundStyle(IrisTheme.secondaryText)
            }
        case .reading:
            HStack(spacing: 12) {
                ProgressView().tint(IrisTheme.accent)
                Text("Reading text…").font(.title3.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        case let .noText(hint):
            message(icon: "text.viewfinder", title: "No text found", body: hint)
        case let .failed(message):
            self.message(icon: "exclamationmark.triangle.fill", title: "Couldn't read text", body: message)
        case .idle:
            message(icon: "text.viewfinder", title: "Nothing read yet",
                    body: "Point the camera at a label, then tap Read Label.")
        }
    }

    private func message(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(IrisTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(.body)
                .foregroundStyle(IrisTheme.secondaryText)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if let result = state.result {
                if speech.isSpeaking {
                    Button {
                        speech.stop()
                    } label: {
                        PrimaryActionLabel(title: "Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(IrisPrimaryButtonStyle())
                    .accessibilityHint("Stops reading aloud")
                } else {
                    Button {
                        speech.speak(result.text)
                    } label: {
                        PrimaryActionLabel(title: "Read Aloud", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(IrisPrimaryButtonStyle())
                    .accessibilityHint("Reads all recognized text aloud")
                }
                if let askIris {
                    Button {
                        speech.stop()
                        askIris(result)
                        dismiss()
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.title3.weight(.bold))
                            .frame(width: 64, height: 64)
                            .background(IrisTheme.raisedSurface, in: RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius))
                    }
                    .accessibilityLabel("Ask Iris about this")
                    .accessibilityHint("Iris explains what this label says")
                }
                Button {
                    UIPasteboard.general.string = result.text
                    UIAccessibility.post(notification: .announcement, argument: "Text copied")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.title3.weight(.bold))
                        .frame(width: 64, height: 64)
                        .background(IrisTheme.raisedSurface, in: RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius))
                }
                .accessibilityLabel("Copy text")
            } else if let retry, state != .reading {
                Button(action: retry) {
                    PrimaryActionLabel(title: "Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(IrisPrimaryButtonStyle())
            }
        }
        .padding(IrisTheme.screenPadding)
        .background(IrisTheme.surface.opacity(0.96))
    }
}
