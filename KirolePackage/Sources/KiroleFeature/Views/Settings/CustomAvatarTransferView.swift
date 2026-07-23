import SwiftUI

// MARK: - Transfer presentation

/// Copy and controls for the full-screen custom-avatar operation surface.
/// Kept independent from the transport state so its edge cases stay unit-testable.
struct CustomAvatarTransferContent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case working
        case warning
        case success
    }

    let title: String
    let message: String
    let progress: Double?
    let progressLabel: String?
    let showsRetry: Bool
    let showsCancel: Bool
    let isCompleted: Bool
    let kind: Kind

    static let preparing = Self(
        title: "Preparing Companion",
        message: "Optimizing the photo for Kirole's E-ink display.",
        progress: nil,
        progressLabel: nil,
        showsRetry: false,
        showsCancel: true,
        isCompleted: false,
        kind: .working
    )

    static func transferring(sentBytes: Int, totalBytes: Int) -> Self {
        let safeTotal = max(totalBytes, 0)
        let fraction: Double
        if safeTotal == 0 {
            fraction = 0
        } else {
            fraction = min(max(Double(sentBytes) / Double(safeTotal), 0), 1)
        }
        return Self(
            title: "Sending to Kirole",
            message: "Keep Kirole nearby and leave the app open until the transfer finishes.",
            progress: fraction,
            progressLabel: "\(Int((fraction * 100).rounded(.down)))%",
            showsRetry: false,
            showsCancel: true,
            isCompleted: false,
            kind: .working
        )
    }

    static let validating = Self(
        title: "Verifying on Kirole",
        message: "The photo has arrived. Kirole is checking it before replacing the current companion.",
        progress: nil,
        progressLabel: nil,
        showsRetry: false,
        showsCancel: true,
        isCompleted: false,
        kind: .working
    )

    static let committing = Self(
        title: "Applying Companion",
        message: "Kirole is safely switching to the new companion. This step can't be cancelled.",
        progress: nil,
        progressLabel: nil,
        showsRetry: false,
        showsCancel: false,
        isCompleted: false,
        kind: .working
    )

    static let erasing = Self(
        title: "Removing from Kirole",
        message: "Kirole is erasing the saved photo. This step can't be cancelled.",
        progress: nil,
        progressLabel: nil,
        showsRetry: false,
        showsCancel: false,
        isCompleted: false,
        kind: .working
    )

    static func interrupted(message: String?) -> Self {
        Self(
            title: "Update Interrupted",
            message: message ?? "Reconnect Kirole, then send the photo again from the beginning.",
            progress: nil,
            progressLabel: nil,
            showsRetry: true,
            showsCancel: true,
            isCompleted: false,
            kind: .warning
        )
    }

    static func failed(message: String, retryAvailable: Bool = true) -> Self {
        Self(
            title: "Couldn't Update Kirole",
            message: message,
            progress: nil,
            progressLabel: nil,
            showsRetry: retryAvailable,
            showsCancel: true,
            isCompleted: false,
            kind: .warning
        )
    }

    static func eraseInterrupted(message: String?) -> Self {
        Self(
            title: "Removal Paused",
            message: message.map { "\($0) The removal is still pending and will continue when Kirole reconnects." }
                ?? "Kirole did not confirm the removal. It is still pending and will continue after reconnecting.",
            progress: nil,
            progressLabel: nil,
            showsRetry: true,
            showsCancel: true,
            isCompleted: false,
            kind: .warning
        )
    }

    static func eraseFailed(message: String) -> Self {
        Self(
            title: "Couldn't Confirm Removal",
            message: "\(message) The removal is still pending and will continue when Kirole reconnects.",
            progress: nil,
            progressLabel: nil,
            showsRetry: true,
            showsCancel: true,
            isCompleted: false,
            kind: .warning
        )
    }

    static let completed = Self(
        title: "Kirole Updated",
        message: "Your companion change was confirmed by Kirole.",
        progress: 1,
        progressLabel: "100%",
        showsRetry: false,
        showsCancel: false,
        isCompleted: true,
        kind: .success
    )
}

extension CustomAvatarOperationState {
    var transferContent: CustomAvatarTransferContent? {
        transferContent(for: nil)
    }

    func transferContent(
        for operationKind: CustomAvatarOperationKind?
    ) -> CustomAvatarTransferContent? {
        switch self {
        case .idle:
            return nil
        case .preparing:
            return .preparing
        case let .transferring(sentBytes, totalBytes):
            return .transferring(sentBytes: sentBytes, totalBytes: totalBytes)
        case .validating:
            return .validating
        case .committing:
            return .committing
        case .erasing:
            return .erasing
        case .success:
            return .completed
        case let .interrupted(message):
            return operationKind?.isErase == true
                ? .eraseInterrupted(message: message)
                : .interrupted(message: message)
        case let .failed(message):
            return operationKind?.isErase == true
                ? .eraseFailed(message: message)
                : .failed(message: message, retryAvailable: operationKind != nil)
        }
    }
}

private extension CustomAvatarOperationKind {
    var isErase: Bool {
        self == .eraseExact || self == .eraseAll
    }
}

// MARK: - Full-screen operation view

struct CustomAvatarTransferView: View {
    let content: CustomAvatarTransferContent
    let actionsDisabled: Bool
    let allowsSecondaryAction: Bool
    let retryActionTitle: String
    let retryActionHint: String
    let secondaryActionTitle: String
    let secondaryActionHint: String
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                statusArtwork

                VStack(spacing: 10) {
                    Text(content.title)
                        .font(.system(size: 25, weight: .bold, design: .serif))
                        .foregroundStyle(theme.colors.primaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("CustomAvatarTransfer_Title")

                    Text(content.message)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 12)
                        .accessibilityIdentifier("CustomAvatarTransfer_Message")
                }

                progress
                    .frame(maxWidth: 320)

                Spacer()
                actions
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .interactiveDismissDisabled(true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CustomAvatarTransfer_Screen")
    }

    @ViewBuilder
    private var statusArtwork: some View {
        ZStack {
            Circle()
                .fill(theme.colors.accentLight)
                .frame(width: 112, height: 112)

            switch content.kind {
            case .working:
                ProgressView()
                    .tint(theme.colors.accent)
                    .scaleEffect(1.6)
                    .accessibilityHidden(true)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .accessibilityHidden(true)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : 1)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if let progress = content.progress, let label = content.progressLabel {
            VStack(spacing: 10) {
                ProgressView(value: progress, total: 1)
                    .tint(theme.colors.accent)
                    .accessibilityValue(label)
                    .accessibilityIdentifier("CustomAvatarTransfer_Progress")

                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.colors.primaryText)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if content.showsRetry {
                Button(retryActionTitle, action: onRetry)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(theme.colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHint(retryActionHint)
                    .accessibilityIdentifier("CustomAvatarTransfer_Retry")
                    .disabled(actionsDisabled)
            }

            if content.showsCancel, allowsSecondaryAction {
                Button(secondaryActionTitle, action: onCancel)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(theme.colors.primaryText.opacity(0.06))
                    .foregroundStyle(theme.colors.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHint(secondaryActionHint)
                    .accessibilityIdentifier("CustomAvatarTransfer_Cancel")
                    .disabled(actionsDisabled)
            }

            if content.isCompleted {
                Button("Done", action: onFinish)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(theme.colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("CustomAvatarTransfer_Done")
                    .disabled(actionsDisabled)
            }
        }
        .frame(maxWidth: 360)
        .opacity(actionsDisabled ? 0.65 : 1)
    }
}
