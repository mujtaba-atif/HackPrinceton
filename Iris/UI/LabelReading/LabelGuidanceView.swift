import SwiftUI

/// Sheet for "Turn to Read": live turning instructions, a readiness meter, then the label reading.
/// Present it at medium height so the camera preview stays visible above it.
struct LabelGuidanceView: View {
    @ObservedObject var service: LabelGuidanceService
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch service.state {
                case .idle:
                    EmptyView()
                case let .guiding(decision):
                    guidancePanel(decision)
                case .capturing, .interpreting:
                    readingPanel
                case .result:
                    if let reading = service.reading { resultPanel(reading) }
                case let .failed(failure):
                    failurePanel(failure)
                }
            }
            .padding(IrisTheme.screenPadding)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(IrisTheme.background.ignoresSafeArea())
        .accessibilityAction(.magicTap, magicTap)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Label("Read Label", systemImage: "text.viewfinder")
                .font(.title2.weight(.bold))
                .foregroundStyle(IrisTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(IrisTheme.primaryText)
                    .frame(width: 52, height: 52)
                    .background(IrisTheme.raisedSurface, in: Circle())
            }
            .accessibilityLabel("Close")
            .accessibilityHint("Stops label reading")
        }
    }

    private func guidancePanel(_ decision: LabelGuidanceDecision) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            instructionCard(title: decision.shortInstruction, systemImage: decision.systemImage)

            VStack(alignment: .leading, spacing: 8) {
                Text("Label visible")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IrisTheme.secondaryText)
                ProgressView(value: service.readiness.score)
                    .tint(IrisTheme.accent)
                    .scaleEffect(x: 1, y: 2.2, anchor: .center)
                    .padding(.vertical, 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Label visible")
            .accessibilityValue("\(Int((service.readiness.score * 100).rounded())) percent")

            Label(service.usesDetectedObject ? "Reading the selected object"
                  : "Reading the center of the camera view",
                  systemImage: service.usesDetectedObject ? "scope" : "viewfinder")
                .font(.footnote)
                .foregroundStyle(IrisTheme.secondaryText)
                .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                actionButton("Read Now", systemImage: "text.magnifyingglass",
                             hint: "Reads whatever is facing the camera now", action: service.readNow)
                actionButton("Stop", systemImage: "stop.fill", hint: "Stops label reading", action: close)
            }
        }
    }

    private var readingPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            instructionCard(title: "Hold still", systemImage: "checkmark.circle.fill")
            HStack(spacing: 12) {
                ProgressView()
                    .tint(IrisTheme.accent)
                Text("Reading the label…")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(IrisTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func resultPanel(_ reading: LabelReading) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if let title = reading.title {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(IrisTheme.primaryText)
                        .accessibilityLabel(reading.titleIsUncertain ? "Possibly \(title). Not certain." : title)
                } else {
                    Text(reading.hasAnyText ? "Name not readable" : "No text read")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(IrisTheme.primaryText)
                }
                if reading.titleIsUncertain {
                    Label("Uncertain reading", systemImage: "questionmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.orange)
                }
                field("Strength", reading.strength)
                field("Directions", reading.directions)
                field(reading.isLikelyPrescription ? "Discard after" : "Date", reading.discardOrExpiration)
                ForEach(Array(reading.warnings.enumerated()), id: \.offset) { _, warning in
                    field("Warning", warning)
                }
                field("Prescription number", reading.rxNumber)
                field("Quantity", reading.quantity)
                field("Refills", reading.refills)
                field("Pharmacy", reading.pharmacy)
                field("Prescriber", reading.prescriber)
                field("Filled", reading.dateFilled)
                if reading.isLikelyPrescription {
                    Text("If anything sounds wrong, confirm with your pharmacist.")
                        .font(.footnote)
                        .foregroundStyle(IrisTheme.secondaryText)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    actionButton("Read Aloud", systemImage: "speaker.wave.2.fill",
                                 hint: "Reads the main details aloud", action: service.readSummary)
                    actionButton("More Details", systemImage: "list.bullet",
                                 hint: "Reads the prescription number, refills, and other details",
                                 action: service.readMoreDetails)
                }
                HStack(spacing: 12) {
                    actionButton("Read Everything", systemImage: "text.alignleft",
                                 hint: "Reads all text found on the label", action: service.readEverything)
                    actionButton("Repeat", systemImage: "arrow.counterclockwise",
                                 hint: "Repeats the last thing Iris said", action: service.repeatLast)
                }
                HStack(spacing: 12) {
                    actionButton("Stop Speaking", systemImage: "speaker.slash.fill",
                                 hint: "Stops speech", action: service.stopSpeaking)
                    actionButton("Read Again", systemImage: "arrow.triangle.2.circlepath",
                                 hint: "Starts turning guidance again", action: retry)
                }
            }
        }
    }

    private func failurePanel(_ failure: LabelGuidanceFailure) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label(failure.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.orange)
                Text(failure.spokenMessage)
                    .font(.body)
                    .foregroundStyle(IrisTheme.secondaryText)
                    .lineSpacing(4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                actionButton("Try Again", systemImage: "arrow.triangle.2.circlepath",
                             hint: "Starts turning guidance again", action: retry)
                actionButton("Close", systemImage: "xmark", hint: "Closes label reading", action: close)
            }
        }
    }

    // MARK: Building blocks

    private func instructionCard(title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(IrisTheme.accent)
                    .frame(width: 64)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(IrisTheme.primaryText)
                    .minimumScaleFactor(0.7)
            }
            if !service.lastMessage.isEmpty {
                Text(service.lastMessage)
                    .font(.body)
                    .foregroundStyle(IrisTheme.secondaryText)
                    .lineSpacing(3)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func field(_ name: String, _ value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IrisTheme.accent)
                Text(value)
                    .font(.body)
                    .foregroundStyle(IrisTheme.primaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func actionButton(_ title: String, systemImage: String, hint: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(IrisTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                        .fill(IrisTheme.raisedSurface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: IrisTheme.controlCornerRadius, style: .continuous)
                        .stroke(IrisTheme.accent.opacity(0.6), lineWidth: 1.5)
                }
                .contentShape(Rectangle())
        }
        .accessibilityHint(hint)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(IrisTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(IrisTheme.hairline, lineWidth: 1)
            }
    }

    /// VoiceOver two-finger double-tap: stop speech, or replay/retry depending on state.
    private func magicTap() {
        if service.speech.isSpeaking {
            service.stopSpeaking()
            return
        }
        switch service.state {
        case .guiding: service.readNow()
        case .result: service.readSummary()
        case .failed, .idle: retry()
        case .capturing, .interpreting: break
        }
    }
}
