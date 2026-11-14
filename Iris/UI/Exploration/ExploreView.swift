import SwiftUI
import UIKit

struct ExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = IrisCameraController()
    @StateObject private var detection = ObjectDetectionService()
    @StateObject private var depth = DepthEstimationService()

    var body: some View {
        ZStack {
            IrisTheme.background
                .ignoresSafeArea()

            ARCameraPreview(session: camera.session)
                .overlay {
                    if camera.state == .running {
                        ObjectDetectionOverlay(snapshot: detection.snapshot, select: detection.select)
                    }
                }
                .ignoresSafeArea()
                .opacity(showsCameraImage ? 1 : 0)

            if camera.state != .running {
                Color.black.opacity(showsCameraImage ? 0.58 : 0.18)
                    .ignoresSafeArea()

                stateOverlay
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if camera.state == .running {
                    DetectedObjectsList(detection: detection, spatialEstimate: depth.estimate) {
                        detection.start(frames: camera.makeFrameStream())
                    }
                }
                controls
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await camera.resumeAfterAppLifecyclePause() }
            case .inactive, .background:
                camera.pauseForAppLifecycle()
            @unknown default:
                camera.pauseForAppLifecycle()
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .running {
                depth.start(frames: camera.makeFrameStream(), supportsSceneDepth: camera.supportsSceneDepth)
                detection.start(frames: camera.makeFrameStream())
            } else {
                depth.stop()
                detection.stop()
            }
            guard let announcement = state.accessibilityAnnouncement else { return }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        .onChange(of: detection.selectedTarget) { _, target in
            depth.setTarget(target)
        }
        .onDisappear {
            depth.stop()
            depth.setTarget(nil)
            detection.reset()
            camera.stop()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label(camera.state.statusLabel, systemImage: camera.state.statusIcon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(camera.state.statusColor)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(IrisTheme.surface.opacity(0.96), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(IrisTheme.hairline, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button(action: exitExplore) {
                Label("Exit", systemImage: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(IrisTheme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(IrisTheme.surface.opacity(0.96), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(IrisTheme.hairline, lineWidth: 1)
                    }
            }
            .accessibilityHint("Stops the camera and returns to the Iris home screen")
        }
        .padding(.horizontal, IrisTheme.screenPadding)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.46))
    }

    @ViewBuilder
    private var stateOverlay: some View {
        ScrollView {
            VStack(spacing: 18) {
                if camera.state.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(IrisTheme.accent)
                        .accessibilityLabel(camera.state.stateTitle)
                } else {
                    Image(systemName: camera.state.stateIcon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(camera.state.statusColor)
                        .accessibilityHidden(true)
                }

                Text(camera.state.stateTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(IrisTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(camera.state.stateMessage)
                    .font(.body)
                    .foregroundStyle(IrisTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                if case let .unavailable(reason) = camera.state, reason.canOpenSettings {
                    Button("Open Settings", action: openSettings)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .padding(.horizontal, 22)
                        .frame(minHeight: 56)
                        .background(IrisTheme.accent, in: Capsule())
                        .accessibilityHint("Opens the Iris camera permission settings")
                }
            }
            .padding(24)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(IrisTheme.surface.opacity(0.96))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(IrisTheme.hairline, lineWidth: 1)
            }
            .padding(IrisTheme.screenPadding)
            .frame(maxWidth: .infinity, minHeight: 420)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            switch camera.state {
            case .running:
                Button(action: camera.pause) {
                    cameraControlLabel(title: "Pause Camera", systemImage: "pause.fill")
                }
                .buttonStyle(CameraSecondaryButtonStyle())
                .accessibilityHint("Pauses the live camera feed")

            case .idle, .stopped:
                startButton(title: "Start Camera", hint: "Requests access and starts the rear camera")

            case .paused:
                startButton(title: "Resume Camera", hint: "Resumes the rear camera")

            case .interrupted:
                cameraControlLabel(title: "Camera Interrupted", systemImage: "pause.circle.fill")
                    .foregroundStyle(IrisTheme.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                            .fill(IrisTheme.raisedSurface)
                    )
                    .accessibilityLabel("Camera interrupted. Waiting for the camera to become available")

            case .failed:
                startButton(title: "Try Again", hint: "Attempts to start the rear camera again")

            case .requestingPermission, .preparing:
                cameraControlLabel(title: "Starting Camera", systemImage: "camera.fill")
                    .foregroundStyle(IrisTheme.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                            .fill(IrisTheme.raisedSurface)
                    )
                    .accessibilityLabel("Starting camera")

            case .unavailable:
                EmptyView()
            }
        }
        .padding(.horizontal, IrisTheme.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.58))
    }

    private func startButton(title: String, hint: String) -> some View {
        Button {
            Task { await camera.start() }
        } label: {
            cameraControlLabel(title: title, systemImage: "camera.fill")
        }
        .buttonStyle(IrisPrimaryButtonStyle())
        .accessibilityHint(hint)
    }

    private func cameraControlLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
    }

    private var showsCameraImage: Bool {
        switch camera.state {
        case .preparing, .running, .paused, .interrupted:
            true
        default:
            false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func exitExplore() {
        depth.stop()
        depth.setTarget(nil)
        detection.reset()
        camera.stop()
        dismiss()
    }
}

private struct CameraSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(IrisTheme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                    .fill(configuration.isPressed
                        ? IrisTheme.raisedSurface.opacity(0.78)
                        : IrisTheme.raisedSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                    .stroke(IrisTheme.accent.opacity(0.72), lineWidth: 2)
            }
    }
}

private extension CameraSessionState {
    var isLoading: Bool {
        self == .requestingPermission || self == .preparing
    }

    var statusLabel: String {
        switch self {
        case .idle, .stopped: "Camera off"
        case .requestingPermission: "Waiting for access"
        case .preparing: "Starting camera"
        case .running: "Camera live"
        case .paused: "Camera paused"
        case .interrupted: "Camera interrupted"
        case .unavailable: "Camera unavailable"
        case .failed: "Camera error"
        }
    }

    var statusIcon: String {
        switch self {
        case .running: "camera.fill"
        case .requestingPermission, .preparing: "hourglass"
        case .paused, .interrupted: "pause.circle.fill"
        case .unavailable, .failed: "exclamationmark.triangle.fill"
        case .idle, .stopped: "camera.slash.fill"
        }
    }

    var stateIcon: String {
        switch self {
        case .paused, .interrupted: "pause.circle.fill"
        case .unavailable, .failed: "exclamationmark.triangle.fill"
        case .requestingPermission, .preparing, .running: "camera.fill"
        case .idle, .stopped: "viewfinder"
        }
    }

    var statusColor: Color {
        switch self {
        case .running: IrisTheme.accent
        case .unavailable, .failed: Color.orange
        default: IrisTheme.primaryText
        }
    }

    var stateTitle: String {
        switch self {
        case .idle: "Ready to explore"
        case .requestingPermission: "Camera access"
        case .preparing: "Starting the camera"
        case .running: "Camera live"
        case .paused: "Camera paused"
        case .interrupted: "Camera interrupted"
        case .stopped: "Exploration stopped"
        case let .unavailable(reason): reason.title
        case .failed: "Camera problem"
        }
    }

    var stateMessage: String {
        switch self {
        case .idle:
            "Start when you’re ready. Iris will ask for camera access the first time."
        case .requestingPermission:
            "Choose Allow so Iris can show the space in front of you."
        case .preparing:
            "Preparing a live rear-camera view."
        case .running:
            "The rear camera is active."
        case .paused:
            "The camera is not capturing new frames. Resume whenever you’re ready."
        case .interrupted:
            "Another system activity interrupted the camera. Resume when it becomes available."
        case .stopped:
            "The camera is off. Start again whenever you’re ready."
        case let .unavailable(reason):
            reason.message
        case let .failed(message):
            message
        }
    }

    var accessibilityAnnouncement: String? {
        switch self {
        case .running: "Camera started"
        case .paused: "Camera paused"
        case .interrupted: "Camera interrupted"
        case .stopped: "Camera stopped"
        case let .unavailable(reason): reason.title + ". " + reason.message
        case let .failed(message): "Camera error. " + message
        case .idle, .requestingPermission, .preparing: nil
        }
    }
}

#Preview {
    NavigationStack {
        ExploreView()
    }
    .preferredColorScheme(.dark)
}

