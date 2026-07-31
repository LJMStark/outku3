import Foundation
import Testing
@testable import KiroleFeature

@Suite("Companion identity presentation", .serialized)
struct CompanionIdentityPresentationTests {
    @Test("built-in selection replaces an in-flight dialogue from the previous identity")
    @MainActor
    func builtInSelectionRegeneratesInFlightDialogue() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let generator = BlockingIdentityDialogueGenerator()
            state.userProfile.companionCharacter = .joy
            state.userProfile.customCompanionId = nil
            state.sharedPetDialogueGenerator = { context, _ in
                await generator.generate(context: context)
            }

            let oldRefresh = Task { @MainActor in
                await state.refreshSharedPetDialogueIfNeeded(force: true)
            }
            await generator.waitUntilFirstCallStarts()

            let selection = Task { @MainActor in
                try await state.selectBuiltInCompanion(.nova)
            }
            for _ in 0..<100 where !state.dialogueForceRefreshRequested {
                try await Task.sleep(for: .milliseconds(1))
            }
            await generator.releaseFirstCall()
            try await selection.value
            await oldRefresh.value

            #expect(await generator.generatedCharacters() == [.joy, .nova])
            #expect(state.currentPetDialogue == "Nova keeps this line focused.")
            state.cancelPendingBLESync()
            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("editing the active custom companion requests an identity DayPack refresh")
    @MainActor
    func activeCustomMetadataEditRequestsIdentityRefresh() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let companionID = UUID()
            let companion = CustomCompanion(
                id: companionID,
                name: "Before",
                relationship: .friend,
                personaVoice: .playful,
                avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: companionID),
                avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: companionID)
            )
            state.customCompanions = [companion]
            state.userProfile.customCompanionId = companionID
            state.sharedPetDialogueGenerator = { _, _ in "Updated companion line." }

            var draft = companion
            draft.name = "After"
            _ = try await state.updateCustomCompanionMetadata(draft)

            #expect(state.pendingBLESyncTrigger == .identityChange)
            state.cancelPendingBLESync()
            try await snapshot.restore(removingAssetIDs: [companionID])
        }
    }

    @Test("Complete/Skip cancellation parks identityChange and resumes it after presentation")
    @MainActor
    func taskActionCancellationPreservesIdentityChange() {
        let state = AppState.makeForTesting()

        state.requestBLESync(
            reason: "identity",
            trigger: .identityChange,
            debounce: .seconds(60)
        )
        #expect(state.pendingBLESyncTrigger == .identityChange)

        state.cancelPendingBLESyncForTaskActionPresentation()
        #expect(state.pendingBLESyncTrigger == nil)
        #expect(state.deferredBLESyncTriggerAfterTaskAction == .identityChange)

        state.resumeDeferredBLESyncAfterTaskActionPresentation()
        #expect(state.deferredBLESyncTriggerAfterTaskAction == nil)
        #expect(state.pendingBLESyncTrigger == .identityChange)

        state.cancelPendingBLESync()
    }

    @Test("ordinary automatic triggers are not re-queued after task-action cancellation")
    @MainActor
    func ordinaryTriggerIsNotPreservedAcrossTaskAction() {
        let state = AppState.makeForTesting()

        state.requestBLESync(
            reason: "focusSessionEnd",
            trigger: .automatic,
            debounce: .seconds(60)
        )
        state.cancelPendingBLESyncForTaskActionPresentation()

        #expect(state.deferredBLESyncTriggerAfterTaskAction == nil)
        #expect(state.pendingBLESyncTrigger == nil)

        state.resumeDeferredBLESyncAfterTaskActionPresentation()
        #expect(state.pendingBLESyncTrigger == nil)
    }

    @Test("makeForTesting installs a no-op BLE sync executor instead of CoreBluetooth")
    @MainActor
    func testingStateInstallsNoOpBLEExecutorByDefault() {
        let state = AppState.makeForTesting()

        #expect(state.bleSyncExecutor != nil)
    }

    @Test("requestBLESync routes through the injected executor")
    @MainActor
    func requestBLESyncUsesInjectedExecutor() async {
        let state = AppState.makeForTesting()
        var executedTriggers: [BLESyncTrigger] = []
        state.bleSyncExecutor = { trigger in
            executedTriggers.append(trigger)
        }

        state.requestBLESync(
            reason: "test-noop-default",
            trigger: .identityChange,
            debounce: .milliseconds(1)
        )
        try? await Task.sleep(for: .milliseconds(20))

        #expect(executedTriggers == [.identityChange])
        state.cancelPendingBLESync()
    }
}

private actor BlockingIdentityDialogueGenerator {
    private var firstCallStarted = false
    private var firstCallStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstCallReleaseContinuation: CheckedContinuation<Void, Never>?
    private var characters: [CompanionCharacter] = []

    func generate(context: AIContext) async -> String {
        characters.append(context.companionCharacter)
        if characters.count == 1 {
            firstCallStarted = true
            firstCallStartedContinuation?.resume()
            firstCallStartedContinuation = nil
            await withCheckedContinuation { continuation in
                firstCallReleaseContinuation = continuation
            }
        }
        return context.companionCharacter == .nova
            ? "Nova keeps this line focused."
            : "Joy keeps this line warm."
    }

    func waitUntilFirstCallStarts() async {
        guard !firstCallStarted else { return }
        await withCheckedContinuation { continuation in
            firstCallStartedContinuation = continuation
        }
    }

    func releaseFirstCall() {
        firstCallReleaseContinuation?.resume()
        firstCallReleaseContinuation = nil
    }

    func generatedCharacters() -> [CompanionCharacter] {
        characters
    }
}

private struct PersistenceSnapshot: Sendable {
    let companions: [CustomCompanion]
    let profile: UserProfile?
    let onboardingProfile: OnboardingProfile?
    let usage: CompanionUsageState?
    let pendingOperation: PendingCustomAvatarOperation?
    let pendingPreview: Data?
    let pendingImage: Data?
    let onboardingGate: Bool

    static func capture() async throws -> Self {
        Self(
            companions: try await LocalStorage.shared.loadCustomCompanions(),
            profile: try await LocalStorage.shared.loadUserProfile(),
            onboardingProfile: try await LocalStorage.shared.loadOnboardingProfile(),
            usage: try await LocalStorage.shared.loadCompanionUsageState(),
            pendingOperation: try await LocalStorage.shared.loadPendingCustomAvatarOperation(),
            pendingPreview: await LocalStorage.shared.loadPendingCustomAvatarPreviewData(),
            pendingImage: await LocalStorage.shared.loadPendingCustomAvatarImageData(),
            onboardingGate: UserDefaults.standard.bool(forKey: "isOnboardingCompleted")
        )
    }

    func restore(removingAssetIDs ids: [UUID]) async throws {
        for id in ids {
            try await LocalStorage.shared.deleteCustomCompanionAssets(id: id)
        }
        try await LocalStorage.shared.saveCustomCompanions(companions)
        if let profile {
            try await LocalStorage.shared.saveUserProfile(profile)
        } else {
            try await LocalStorage.shared.deleteFile(named: "user_profile.json")
        }
        if let onboardingProfile {
            try await LocalStorage.shared.saveOnboardingProfile(onboardingProfile)
        } else {
            try await LocalStorage.shared.deleteFile(named: "onboarding_profile.json")
        }
        if let usage {
            try await LocalStorage.shared.saveCompanionUsageState(usage)
        } else {
            try await LocalStorage.shared.deleteFile(named: "companion_usage_state.json")
        }
        try await LocalStorage.shared.clearPendingCustomAvatarOperation()
        if let pendingOperation {
            try await LocalStorage.shared.savePendingCustomAvatarOperation(pendingOperation)
        }
        if let pendingPreview, let pendingImage {
            try await LocalStorage.shared.savePendingCustomAvatarAssets(
                previewData: pendingPreview,
                imageData: pendingImage
            )
        }
        UserDefaults.standard.set(onboardingGate, forKey: "isOnboardingCompleted")
    }
}
