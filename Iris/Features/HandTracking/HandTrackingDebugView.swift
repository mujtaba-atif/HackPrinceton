import SwiftUI
import UIKit

/// Isolated developer screen for checking hand tracking on device.
/// It owns its own `IrisCameraController`, which is the only camera session while this
/// screen is shown (it is never presented alongside `ExploreView`). Hand tracking itself
/// only subscribes to that controller's frame broker.
struct HandTrackingDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = IrisCameraController()
    @StateObject private var hands = HandTrackingService()

    var body: some View {
        ZStack {
            IrisTheme.background.ignoresSafeArea()

            ARCameraPreview(session: camera.session)
                .overlay {
                    if camera.state == .running {
                        HandTrackingOverlay(snapshot: hands.snapshot)
                    }
                }
                .ignoresSafeArea()
                .opacity(isCameraVisible ? 1 : 0)

            if camera.state != .running {
                messageCard
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await camera.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.resumeAfterAppLifecyclePause() }
            } else {
                camera.pauseForAppLifecycle()
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .running {
                hands.start(frames: camera.makeFrameStream())
            } else {
                hands.stop()
            }
        }
        .onChange(of: hands.snapshot.overallState) { _, state in
            guard state == .tracking || state == .lost else { return }
            UIAccessibility.post(notification: .announcement, argument: state.title)
        }
        .onDisappear {
            hands.reset()
            camera.stop()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(hands.snapshot.overallState == .tracking ? IrisTheme.accent : IrisTheme.primaryText)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(IrisTheme.surface.opacity(0.96), in: Capsule())
                .overlay { Capsule().stroke(IrisTheme.hairline, lineWidth: 1) }
                .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                hands.reset()
                camera.stop()
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(IrisTheme.primaryText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(IrisTheme.surface.opacity(0.96), in: Capsule())
                    .overlay { Capsule().stroke(IrisTheme.hairline, lineWidth: 1) }
            }
            .accessibilityHint("Stops the camera and returns to the home screen")
        }
        .padding(.horizontal, IrisTheme.screenPadding)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.46))
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hand = hands.primaryHand {
                row("Hand", "\(hand.chirality.title) · \(hand.state.title)")
                row("Confidence", String(format: "%.0f%% · %d joints", hand.confidence * 100, hand.landmarks.count))
                row("Center", format(hand.center))
                row("Fingertip", hand.pointingTip.map(format) ?? "—")
                if hands.snapshot.hands.count > 1 {
                    row("Hands", "\(hands.snapshot.hands.count)")
                }
            } else {
                Text(camera.state == .running ? "Hold your hand in front of the rear camera." : "Camera is not running.")
                    .font(.body)
                    .foregroundStyle(IrisTheme.secondaryText)
            }
            if case let .unavailable(reason) = hands.readiness {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                .fill(IrisTheme.surface.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                .stroke(IrisTheme.hairline, lineWidth: 1)
        }
        .padding(.horizontal, IrisTheme.screenPadding)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.58))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var messageCard: some View {
        VStack(spacing: 16) {
            Text(cameraMessage)
                .font(.body)
                .foregroundStyle(IrisTheme.secondaryText)
                .multilineTextAlignment(.center)

            switch camera.state {
            case let .unavailable(reason) where reason.canOpenSettings:
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.headline.weight(.bold))
            case .idle, .paused, .stopped, .failed:
                Button {
                    Task { await camera.start() }
                } label: {
                    PrimaryActionLabel(title: "Start Camera", systemImage: "camera.fill")
                }
                .buttonStyle(IrisPrimaryButtonStyle())
            default:
                EmptyView()
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(IrisTheme.surface.opacity(0.96)))
        .padding(IrisTheme.screenPadding)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(IrisTheme.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(IrisTheme.primaryText)
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
    }

    private func format(_ point: CGPoint) -> String {
        String(format: "x %.2f  y %.2f", point.x, point.y)
    }

    private var isCameraVisible: Bool {
        switch camera.state {
        case .preparing, .running, .paused, .interrupted: true
        default: false
        }
    }

    private var statusText: String {
        camera.state == .running ? hands.snapshot.overallState.title : "Hand tracking debug"
    }

    private var statusIcon: String {
        switch hands.snapshot.overallState {
        case .tracking: "hand.raised.fill"
        case .limited, .lost: "hand.raised"
        case .searching: "viewfinder"
        case .suspended: "hand.raised.slash"
        }
    }

    private var cameraMessage: String {
        switch camera.state {
        case .idle, .stopped: "Start the camera to test hand tracking."
        case .requestingPermission, .preparing: "Starting the camera…"
        case .running: ""
        case .paused: "Camera paused."
        case .interrupted: "Camera interrupted. Waiting for it to become available."
        case let .unavailable(reason): reason.title + ". " + reason.message
        case let .failed(message): message
        }
    }
}

#Preview {
    NavigationStack {
        HandTrackingDebugView()
    }
    .preferredColorScheme(.dark)
}
