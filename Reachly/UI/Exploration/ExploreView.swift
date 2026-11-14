import SwiftUI
import UIKit

struct ExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = ReachlyCameraController()

    var body: some View {
        ZStack {
            ReachlyTheme.background
                .ignoresSafeArea()

            ARCameraPreview(session: camera.session)
                .ignoresSafeArea()
                .opacity(showsCameraImage ? 1 : 0)
                .accessibilityHidden(true)

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
            controls
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
            guard let announcement = state.accessibilityAnnouncement else { return }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        .onDisappear {
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
                .background(ReachlyTheme.surface.opacity(0.96), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(ReachlyTheme.hairline, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button(action: exitExplore) {
                Label("Exit", systemImage: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ReachlyTheme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(ReachlyTheme.surface.opacity(0.96), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(ReachlyTheme.hairline, lineWidth: 1)
                    }
            }
            .accessibilityHint("Stops the camera and returns to the Reachly home screen")
        }
        .padding(.horizontal, ReachlyTheme.screenPadding)
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
                        .tint(ReachlyTheme.accent)
                        .accessibilityLabel(camera.state.stateTitle)
                } else {
                    Image(systemName: camera.state.stateIcon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(camera.state.statusColor)
                        .accessibilityHidden(true)
                }

                Text(camera.state.stateTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ReachlyTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(camera.state.stateMessage)
                    .font(.body)
                    .foregroundStyle(ReachlyTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                if case let .unavailable(reason) = camera.state, reason.canOpenSettings {
                    Button("Open Settings", action: openSettings)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .padding(.horizontal, 22)
                        .frame(minHeight: 56)
                        .background(ReachlyTheme.accent, in: Capsule())
                        .accessibilityHint("Opens the Reachly camera permission settings")
                }
            }
            .padding(24)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ReachlyTheme.surface.opacity(0.96))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(ReachlyTheme.hairline, lineWidth: 1)
            }
            .padding(ReachlyTheme.screenPadding)
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
                    .foregroundStyle(ReachlyTheme.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: ReachlyTheme.controlCornerRadius, style: .continuous)
                            .fill(ReachlyTheme.raisedSurface)
                    )
                    .accessibilityLabel("Camera interrupted. Waiting for the camera to become available")

            case .failed:
                startButton(title: "Try Again", hint: "Attempts to start the rear camera again")

            case .requestingPermission, .preparing:
                cameraControlLabel(title: "Starting Camera", systemImage: "camera.fill")
                    .foregroundStyle(ReachlyTheme.secondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: ReachlyTheme.controlCornerRadius, style: .continuous)
                            .fill(ReachlyTheme.raisedSurface)
                    )
                    .accessibilityLabel("Starting camera")

            case .unavailable:
                EmptyView()
            }
        }
        .padding(.horizontal, ReachlyTheme.screenPadding)
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
        .buttonStyle(ReachlyPrimaryButtonStyle())
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
        camera.stop()
        dismiss()
    }
}

private struct CameraSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ReachlyTheme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: ReachlyTheme.controlCornerRadius, style: .continuous)
                    .fill(configuration.isPressed
                        ? ReachlyTheme.raisedSurface.opacity(0.78)
                        : ReachlyTheme.raisedSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ReachlyTheme.controlCornerRadius, style: .continuous)
                    .stroke(ReachlyTheme.accent.opacity(0.72), lineWidth: 2)
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
        case .running: ReachlyTheme.accent
        case .unavailable, .failed: Color.orange
        default: ReachlyTheme.primaryText
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
            "Start when you’re ready. Reachly will ask for camera access the first time."
        case .requestingPermission:
            "Choose Allow so Reachly can show the space in front of you."
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

