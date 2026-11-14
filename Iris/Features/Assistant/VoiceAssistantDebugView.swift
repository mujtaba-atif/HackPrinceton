import SwiftUI

/// Isolated test screen for OCR, speech, voice commands, and the ElevenLabs assistant.
/// Owns its own `IrisCameraController` (the only camera session while shown) and object
/// detection, mirroring how Explore will host `VoiceAssistantPanel`, without editing Explore.
struct VoiceAssistantDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = IrisCameraController()
    @StateObject private var detection = ObjectDetectionService()
    @StateObject private var assistant = VoiceAssistantCoordinator()

    var body: some View {
        ZStack {
            IrisTheme.background.ignoresSafeArea()

            ARCameraPreview(session: camera.session)
                .overlay {
                    if camera.state == .running {
                        ObjectDetectionOverlay(snapshot: detection.snapshot, select: detection.select)
                    }
                }
                .ignoresSafeArea()

            if camera.state != .running {
                VStack(spacing: 16) {
                    Text(cameraMessage)
                        .font(.body)
                        .foregroundStyle(IrisTheme.secondaryText)
                        .multilineTextAlignment(.center)
                    if camera.state != .requestingPermission, camera.state != .preparing {
                        Button {
                            Task { await camera.start() }
                        } label: {
                            PrimaryActionLabel(title: "Start Camera", systemImage: "camera.fill")
                        }
                        .buttonStyle(IrisPrimaryButtonStyle())
                    }
                }
                .padding(24)
                .frame(maxWidth: 440)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(IrisTheme.surface.opacity(0.96)))
                .padding(IrisTheme.screenPadding)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Label("Voice assistant debug", systemImage: "waveform")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(IrisTheme.surface.opacity(0.96), in: Capsule())
                Spacer()
                Button {
                    close()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(IrisTheme.surface.opacity(0.96), in: Capsule())
                }
                .accessibilityHint("Stops the camera and microphone and returns home")
            }
            .foregroundStyle(IrisTheme.primaryText)
            .padding(.horizontal, IrisTheme.screenPadding)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.46))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VoiceAssistantPanel(assistant: assistant)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await camera.start() }
        .onAppear {
            assistant.attach(
                frames: { [camera] in camera.makeFrameStream() },
                detection: { [detection] in detection.snapshot },
                select: { [detection] id in detection.select(id) },
                isCameraRunning: { [camera] in camera.state == .running }
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.resumeAfterAppLifecyclePause() }
            } else {
                assistant.shutdown()
                camera.pauseForAppLifecycle()
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .running {
                detection.start(frames: camera.makeFrameStream())
            } else {
                detection.stop()
            }
        }
        .onDisappear(perform: shutdown)
    }

    private var cameraMessage: String {
        switch camera.state {
        case .requestingPermission, .preparing: "Starting the camera…"
        case let .unavailable(reason): reason.title + ". " + reason.message
        case let .failed(message): message
        default: "Start the camera to test the voice assistant."
        }
    }

    private func close() {
        shutdown()
        dismiss()
    }

    private func shutdown() {
        assistant.shutdown()
        detection.reset()
        camera.stop()
    }
}
