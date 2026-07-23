import Foundation
import Testing
@testable import KiroleFeature

@Suite("Custom avatar UI state")
struct CustomAvatarUIStateTests {
    @Test("transfer progress is determinate and clamped to the available bytes")
    func transferProgressIsClamped() {
        let halfway = CustomAvatarTransferContent.transferring(sentBytes: 50, totalBytes: 100)
        #expect(halfway.progress == 0.5)
        #expect(halfway.progressLabel == "50%")
        #expect(halfway.showsRetry == false)
        #expect(halfway.showsCancel)

        let overrun = CustomAvatarTransferContent.transferring(sentBytes: 120, totalBytes: 100)
        #expect(overrun.progress == 1)
        #expect(overrun.progressLabel == "100%")

        let empty = CustomAvatarTransferContent.transferring(sentBytes: 0, totalBytes: 0)
        #expect(empty.progress == 0)
        #expect(empty.progressLabel == "0%")
    }

    @Test("validation and commit remain distinct after transfer reaches 100 percent")
    func validationAndCommitHaveDistinctCopy() {
        let validating = CustomAvatarTransferContent.validating
        let committing = CustomAvatarTransferContent.committing

        #expect(validating.title == "Verifying on Kirole")
        #expect(validating.progress == nil)
        #expect(validating.showsCancel)
        #expect(committing.title == "Applying Companion")
        #expect(committing.showsCancel == false)
        #expect(validating != committing)
    }

    @Test("failure can retry or cancel while success can only finish")
    func terminalActionsMatchRecoveryRules() {
        let failed = CustomAvatarTransferContent.failed(message: "Connection lost")
        #expect(failed.showsRetry)
        #expect(failed.showsCancel)
        #expect(failed.message == "Connection lost")

        let authoritativeFailure = CustomAvatarOperationState.failed("Kirole kept the previous companion")
            .transferContent(for: nil)
        #expect(authoritativeFailure?.showsRetry == false)
        #expect(authoritativeFailure?.showsCancel == true)

        let completed = CustomAvatarTransferContent.completed
        #expect(completed.showsRetry == false)
        #expect(completed.showsCancel == false)
        #expect(completed.isCompleted)
    }

    @Test("an unconfirmed erase is closed rather than falsely cancelled")
    func eraseRecoveryCopyExplainsPendingRemoval() {
        let interrupted = CustomAvatarOperationState.interrupted("Connection lost")
            .transferContent(for: .eraseExact)

        #expect(interrupted?.title == "Removal Paused")
        #expect(interrupted?.showsRetry == true)
        #expect(interrupted?.showsCancel == true)
        #expect(interrupted?.message.contains("still pending") == true)
    }

    @Test("onboarding custom companion requires a connected Kirole")
    func onboardingCustomCompanionConnectionGuard() {
        #expect(
            OnboardingCustomCompanionGuard.validationMessage(
                hasCustomCompanionDraft: true,
                isDeviceConnected: false
            ) != nil
        )
        #expect(
            OnboardingCustomCompanionGuard.validationMessage(
                hasCustomCompanionDraft: true,
                isDeviceConnected: true
            ) == nil
        )
        #expect(
            OnboardingCustomCompanionGuard.validationMessage(
                hasCustomCompanionDraft: false,
                isDeviceConnected: false
            ) == nil
        )
    }

    @Test("domain operation states map to the matching full-screen content")
    func domainStateMapsToTransferContent() {
        #expect(CustomAvatarOperationState.idle.transferContent == nil)
        #expect(
            CustomAvatarOperationState.transferring(sentBytes: 25, totalBytes: 100)
                .transferContent?.progressLabel == "25%"
        )
        #expect(
            CustomAvatarOperationState.interrupted("Device disconnected")
                .transferContent?.message == "Device disconnected"
        )
        #expect(CustomAvatarOperationState.success.transferContent?.isCompleted == true)
    }

    @Test("photo transaction start dismisses the editor and leaves progress to the full-screen view")
    @MainActor
    func photoTransactionStartDismissesEditor() {
        #expect(!CreateCustomCompanionSheet.shouldDismissEditor(for: .idle))
        #expect(CreateCustomCompanionSheet.shouldDismissEditor(for: .preparing))
        #expect(CreateCustomCompanionSheet.shouldDismissEditor(
            for: .transferring(sentBytes: 1, totalBytes: 2)
        ))
        #expect(CreateCustomCompanionSheet.shouldDismissEditor(for: .validating))
        #expect(CreateCustomCompanionSheet.shouldDismissEditor(for: .committing))
        #expect(!CreateCustomCompanionSheet.shouldDismissEditor(for: .failed("failed")))
    }

    @Test("delete confirmation does not promise device erase without a known device")
    func deleteConfirmationMatchesKnownDeviceState() {
        #expect(CharacterSwitcherSheet.deleteConfirmationMessage(
            isConnected: false,
            hasKnownDevice: true
        ).contains("next time it connects"))
        #expect(CharacterSwitcherSheet.deleteConfirmationMessage(
            isConnected: false,
            hasKnownDevice: false
        ) == "This removes the companion from this iPhone. No known Kirole device is scheduled for photo removal.")
    }

    @Test("editing draft preserves companion identity and asset references")
    func editingDraftPreservesIdentity() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 123)
        let companion = CustomCompanion(
            id: id,
            name: "Mochi",
            relationship: .pet,
            personaVoice: .playful,
            customPrompt: "",
            curiosityLevel: 0.8,
            humorLevel: 0.7,
            strictnessLevel: 0.2,
            backstory: "Sleeps near the window.",
            sensitiveBoundary: "Skip health jokes.",
            avatarPreviewFileName: "preview.png",
            avatarPixelsFileName: "avatar.png",
            createdAt: createdAt,
            updatedAt: createdAt
        )

        var draft = CustomCompanionFormDraft(companion: companion)
        draft.name = "Mochi II"
        draft.relationship = .friend

        let updated = draft.updating(companion, now: Date(timeIntervalSince1970: 456))
        #expect(updated.id == id)
        #expect(updated.createdAt == createdAt)
        #expect(updated.avatarPreviewFileName == "preview.png")
        #expect(updated.avatarPixelsFileName == "avatar.png")
        #expect(updated.name == "Mochi II")
        #expect(updated.relationship == .friend)
        #expect(updated.updatedAt == Date(timeIntervalSince1970: 456))
    }
}
