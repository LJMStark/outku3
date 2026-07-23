import Foundation
import Testing
@testable import KiroleFeature

@Suite("Custom avatar recovery", .serialized)
@MainActor
struct CustomAvatarRecoveryTests {
    @Test("inactive committed inventory is safe to overwrite when the old App selection is built-in")
    func builtInSelectionRetransmitsOverInactiveStoredAvatar() async throws {
        let state = AppState.makeForTesting()
        let deviceID = UUID()
        let candidate = makeCompanion(id: UUID(), name: "Candidate")
        let kriData = Data([1, 2, 3])
        let operation = makePendingApply(
            companion: candidate,
            oldID: nil,
            deviceID: deviceID,
            kriData: kriData,
            phase: .awaitingValidation
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .interrupted("recover")
        state.customAvatarConnectionProvider = { (true, deviceID) }
        state.avatarControlSender = { command in
            guard case .query(let operationID) = command else {
                Issue.record("Expected inventory query")
                return
            }
            state.handleAvatarControlResult(
                AvatarControlResult(
                    operationID: operationID,
                    status: .state,
                    avatarState: .committed,
                    customActive: false,
                    avatarID: UUID(),
                    byteLength: 512,
                    crc32: 0x1234_5678
                )
            )
        }
        let generation = state.beginCustomAvatarOperationGeneration()

        let disposition = try await state.pendingApplyRecoveryDisposition(
            operation,
            generation: generation
        )

        if case .retransmit = disposition {} else {
            Issue.record("Inactive stored avatar should allow a full retransmit")
        }
    }

    @Test("retry commits a matching staged image without retransferring and ignores late staged")
    func stagedRecoverySkipsFullTransfer() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let oldID = UUID()
            let candidateID = UUID()
            let deviceID = UUID()
            let old = makeCompanion(id: oldID, name: "Old")
            let candidate = makeCompanion(id: candidateID, name: "Candidate")
            let png = try validPNG()
            let kriData = try KRIEncoder.encode(pngData: png)
            let operation = makePendingApply(
                companion: candidate,
                oldID: oldID,
                deviceID: deviceID,
                kriData: kriData,
                phase: .awaitingValidation
            )
            try await LocalStorage.shared.savePendingCustomAvatarAssets(
                previewData: png,
                imageData: png
            )
            try await LocalStorage.shared.savePendingCustomAvatarOperation(operation)
            state.customCompanions = [old]
            state.userProfile.customCompanionId = oldID
            state.pendingCustomAvatarOperation = operation
            state.customAvatarOperationState = .interrupted("retry")
            state.customAvatarConnectionProvider = { (true, deviceID) }
            var didTransferFrame = false
            state.customAvatarFrameSender = { _, _, _, _ in didTransferFrame = true }
            state.avatarControlSender = { command in
                switch command {
                case .query(let operationID):
                    state.handleAvatarControlResult(
                        AvatarControlResult(
                            operationID: operationID,
                            status: .state,
                            avatarState: .staged,
                            customActive: true,
                            avatarID: candidateID,
                            byteLength: UInt32(kriData.count),
                            crc32: CRC32.ieee(kriData)
                        )
                    )
                case .commit(let operationID, let avatarID):
                    state.handleAvatarControlResult(
                        AvatarControlResult(
                            operationID: operationID,
                            status: .staged,
                            avatarState: .staged,
                            customActive: true,
                            avatarID: avatarID,
                            byteLength: UInt32(kriData.count),
                            crc32: CRC32.ieee(kriData)
                        )
                    )
                    state.handleAvatarControlResult(
                        AvatarControlResult(
                            operationID: operationID,
                            status: .committed,
                            avatarState: .committed,
                            customActive: true,
                            avatarID: avatarID,
                            byteLength: UInt32(kriData.count),
                            crc32: CRC32.ieee(kriData)
                        )
                    )
                default:
                    Issue.record("Unexpected avatar command")
                }
            }

            await state.retryCustomAvatarOperation()

            #expect(!didTransferFrame)
            #expect(state.userProfile.customCompanionId == candidateID)
            #expect(state.customAvatarOperationState == .success)

            try await snapshot.restore(removingAssetIDs: [oldID, candidateID])
        }
    }

    @Test("query never finalizes a committed candidate that is not active")
    func inactiveCommittedCandidateDoesNotChangeIdentity() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let candidate = makeCompanion(id: UUID(), name: "Candidate")
            let deviceID = UUID()
            let png = try validPNG()
            let kriData = try KRIEncoder.encode(pngData: png)
            let operation = makePendingApply(
                companion: candidate,
                oldID: nil,
                deviceID: deviceID,
                kriData: kriData,
                phase: .awaitingCommitResult
            )
            try await LocalStorage.shared.savePendingCustomAvatarAssets(
                previewData: png,
                imageData: png
            )
            try await LocalStorage.shared.savePendingCustomAvatarOperation(operation)
            state.pendingCustomAvatarOperation = operation
            state.customAvatarOperationState = .interrupted("query")
            state.customAvatarConnectionProvider = { (true, deviceID) }
            var didCommit = false
            state.avatarControlSender = { command in
                switch command {
                case .query(let operationID):
                    state.handleAvatarControlResult(
                        AvatarControlResult(
                            operationID: operationID,
                            status: .state,
                            avatarState: .committed,
                            customActive: false,
                            avatarID: candidate.id,
                            byteLength: UInt32(kriData.count),
                            crc32: CRC32.ieee(kriData)
                        )
                    )
                case .commit:
                    didCommit = true
                default:
                    Issue.record("Unexpected avatar command")
                }
            }

            await state.retryCustomAvatarOperation()

            #expect(!didCommit)
            #expect(state.userProfile.customCompanionId == nil)
            #expect(state.pendingCustomAvatarOperation == nil)
            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation() == nil)
            if case .failed = state.customAvatarOperationState {} else {
                Issue.record("Inactive committed inventory must fail without local commit")
            }
            do {
                try state.ensureNoCustomAvatarOperation()
            } catch {
                Issue.record("An authoritative failed query must not block the next avatar operation")
            }

            try await snapshot.restore(removingAssetIDs: [candidate.id])
        }
    }

    @Test("pending operation never replays on a different device")
    func retryRejectsDifferentDevice() async {
        let state = AppState.makeForTesting()
        let deviceA = UUID()
        let deviceB = UUID()
        let candidate = makeCompanion(id: UUID(), name: "Candidate")
        let operation = makePendingApply(
            companion: candidate,
            oldID: nil,
            deviceID: deviceA,
            kriData: Data([1]),
            phase: .prepared
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .interrupted("retry")
        state.customAvatarConnectionProvider = { (true, deviceB) }
        var didSendCommand = false
        state.avatarControlSender = { _ in didSendCommand = true }

        await state.retryCustomAvatarOperation()

        state.handleAvatarControlResult(
            AvatarControlResult(
                operationID: operation.operationID,
                status: .staged,
                avatarState: .staged,
                customActive: true,
                avatarID: candidate.id,
                byteLength: 1,
                crc32: CRC32.ieee(Data([1]))
            )
        )

        #expect(!didSendCommand)
        #expect(state.pendingCustomAvatarOperation?.operationID == operation.operationID)
        #expect(state.bufferedAvatarControlResults[operation.operationID] == nil)
        if case .failed(let message) = state.customAvatarOperationState {
            #expect(message.contains("started this companion image operation"))
        } else {
            Issue.record("Different-device retry must fail visibly")
        }
    }

    @Test("DeviceWake with unrelated inventory defers the decision to query recovery")
    func builtInRollbackDefersThirdAvatarInventoryToQuery() async {
        let state = AppState.makeForTesting()
        let deviceID = UUID()
        let candidate = makeCompanion(id: UUID(), name: "Candidate")
        let kriData = Data([1, 2, 3])
        let operation = makePendingApply(
            companion: candidate,
            oldID: nil,
            deviceID: deviceID,
            kriData: kriData,
            phase: .awaitingValidation
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .interrupted("recover")
        state.customAvatarConnectionProvider = { (true, deviceID) }

        let needsRecovery = await state.reconcileCustomAvatarInventory(
            hasImage: true,
            avatarID: UUID(),
            byteLength: 99,
            reportedCRC32: 99
        )

        #expect(needsRecovery)
        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.userProfile.customCompanionId == nil)
        #expect(state.customAvatarOperationState == .interrupted("recover"))
    }

    @Test("background pauses pre-commit work while disconnect interrupts commit recovery")
    func interruptionBoundariesPreservePendingOperation() {
        let state = AppState.makeForTesting()
        let companion = makeCompanion(id: UUID(), name: "Candidate")
        var operation = makePendingApply(
            companion: companion,
            oldID: nil,
            deviceID: UUID(),
            kriData: Data([1]),
            phase: .transferring
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .transferring(sentBytes: 1, totalBytes: 2)

        state.interruptCustomAvatarOperationForBackground()

        #expect(state.pendingCustomAvatarOperation?.operationID == operation.operationID)
        if case .interrupted = state.customAvatarOperationState {} else {
            Issue.record("Background must interrupt a pre-commit transfer")
        }

        operation.phase = .awaitingCommitResult
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .committing
        state.interruptCustomAvatarOperationForBackground()
        #expect(state.customAvatarOperationState == .committing)
        #expect(!state.canCancelCustomAvatarOperation)

        state.handleCustomAvatarDeviceDisconnected()
        if case .interrupted = state.customAvatarOperationState {} else {
            Issue.record("Disconnect must immediately interrupt result waiting")
        }
        #expect(state.pendingCustomAvatarOperation?.operationID == operation.operationID)
        #expect(!state.canCancelCustomAvatarOperation)
    }

    @Test("built-in selection waits for abort before changing identity")
    func builtInSelectionWaitsForAbort() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let customID = UUID()
            let deviceID = UUID()
            let companion = makeCompanion(id: customID, name: "Current")
            let operation = makePendingApply(
                companion: companion,
                oldID: customID,
                deviceID: deviceID,
                kriData: Data([1]),
                phase: .awaitingValidation
            )
            state.customCompanions = [companion]
            state.userProfile.customCompanionId = customID
            state.pendingCustomAvatarOperation = operation
            state.customAvatarOperationState = .validating
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.avatarControlSender = { command in
                guard case .abort(let operationID) = command else {
                    Issue.record("Expected abort before switching identity")
                    return
                }
                #expect(state.userProfile.customCompanionId == customID)
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .aborted,
                        avatarState: .committed,
                        customActive: true,
                        avatarID: customID,
                        byteLength: 1,
                        crc32: 1
                    )
                )
            }

            try await state.selectBuiltInCompanion(.nova)

            #expect(state.userProfile.customCompanionId == nil)
            #expect(state.userProfile.companionCharacter == .nova)
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [customID])
        }
    }

    @Test("built-in selection projects its saved binding days")
    func builtInSelectionRestoresIntimacyProjection() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            var usage = CompanionUsageState()
            usage.setProgress(
                CompanionBindingProgress(totalUsedDays: 15),
                for: .nova
            )
            try await LocalStorage.shared.saveCompanionUsageState(usage)
            state.userProfile.companionCharacter = .joy
            state.userProfile.customCompanionId = UUID()
            state.userProfile.intimacyStage = .acquaintance

            try await state.selectBuiltInCompanion(.nova)

            #expect(state.userProfile.customCompanionId == nil)
            #expect(state.userProfile.intimacyStage == .closeFriend)

            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("onboarding retry commits once and completes the gate")
    func onboardingRetryCompletesWithoutDuplicateCompanion() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            UserDefaults.standard.set(false, forKey: "isOnboardingCompleted")
            let state = AppState.makeForTesting()
            let deviceID = UUID()
            let companionID = UUID()
            let png = try validPNG()
            let kriData = try KRIEncoder.encode(pngData: png)
            let onboarding = OnboardingProfile(
                companionCharacter: .joy,
                onboardingCompletedAt: Date(),
                customCompanionName: "Onboarding Friend",
                customCompanionRelationship: .friend,
                customCompanionVoice: .playful,
                customAvatarPreviewData: png,
                customAvatarImageData: png
            )
            let companion = CustomCompanion(
                id: companionID,
                name: "Onboarding Friend",
                relationship: .friend,
                personaVoice: .playful,
                avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: companionID),
                avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: companionID)
            )
            let operation = makePendingApply(
                companion: companion,
                oldID: nil,
                deviceID: deviceID,
                kriData: kriData,
                phase: .awaitingValidation
            )
            try await LocalStorage.shared.savePendingCustomAvatarAssets(
                previewData: png,
                imageData: png
            )
            try await LocalStorage.shared.savePendingCustomAvatarOperation(operation)
            state.onboardingProfile = onboarding
            state.userProfile = UserProfile.from(onboarding: onboarding, merging: .default)
            state.pendingCustomAvatarOperation = operation
            state.customAvatarOperationState = .interrupted("retry")
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.avatarControlSender = { command in
                switch command {
                case .query(let operationID):
                    state.handleAvatarControlResult(
                        AvatarControlResult(
                            operationID: operationID,
                            status: .state,
                            avatarState: .staged,
                            customActive: false,
                            avatarID: companionID,
                            byteLength: UInt32(kriData.count),
                            crc32: CRC32.ieee(kriData)
                        )
                    )
                case .commit(let operationID, let avatarID):
                    state.handleAvatarControlResult(
                        AvatarControlResult(
                            operationID: operationID,
                            status: .committed,
                            avatarState: .committed,
                            customActive: true,
                            avatarID: avatarID,
                            byteLength: UInt32(kriData.count),
                            crc32: CRC32.ieee(kriData)
                        )
                    )
                default:
                    Issue.record("Unexpected avatar command")
                }
            }

            await state.retryCustomAvatarOperation()

            #expect(state.customCompanions.map(\.id) == [companionID])
            #expect(UserDefaults.standard.bool(forKey: "isOnboardingCompleted"))

            state.completeOnboarding(with: onboarding)
            try await Task.sleep(for: .milliseconds(50))
            #expect(state.customCompanions.map(\.id) == [companionID])

            try await snapshot.restore(removingAssetIDs: [companionID])
        }
    }

    @Test("committed result arriving before commit phase is discarded")
    func prematureCommittedResultIsNotBuffered() {
        let state = AppState.makeForTesting()
        let deviceID = UUID()
        let candidate = makeCompanion(id: UUID(), name: "Candidate")
        let operation = makePendingApply(
            companion: candidate,
            oldID: nil,
            deviceID: deviceID,
            kriData: Data([1]),
            phase: .awaitingValidation
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .validating
        state.customAvatarConnectionProvider = { (true, deviceID) }
        state.avatarControlExpectedBufferedStatus = .staged

        state.handleAvatarControlResult(
            AvatarControlResult(
                operationID: operation.operationID,
                status: .committed,
                avatarState: .committed,
                customActive: true,
                avatarID: candidate.id,
                byteLength: 1,
                crc32: CRC32.ieee(Data([1]))
            )
        )

        #expect(state.bufferedAvatarControlResults[operation.operationID] == nil)
    }

    @Test("offline cancellation keeps an abort marker and reconnect flushes it before retransmission")
    func offlineCancellationResumesAsAbort() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let deviceID = UUID()
            let oldID = UUID()
            let candidate = makeCompanion(id: UUID(), name: "Candidate")
            let operation = makePendingApply(
                companion: candidate,
                oldID: oldID,
                deviceID: deviceID,
                kriData: Data([1]),
                phase: .transferring
            )
            state.pendingCustomAvatarOperation = operation
            state.userProfile.customCompanionId = oldID
            state.customAvatarOperationState = .interrupted("offline")
            state.customAvatarConnectionProvider = { (false, deviceID) }
            var sentFrame = false
            var sentAbort = false
            state.customAvatarFrameSender = { _, _, _, _ in sentFrame = true }
            state.avatarControlSender = { command in
                guard case .abort(let operationID) = command else {
                    Issue.record("Expected abort")
                    return
                }
                sentAbort = true
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .aborted,
                        avatarState: .committed,
                        customActive: true,
                        avatarID: oldID,
                        byteLength: 1,
                        crc32: 1
                    )
                )
            }

            try await state.cancelCustomAvatarOperation()

            #expect(state.pendingCustomAvatarOperation?.phase == .awaitingAbortResult)
            #expect(state.customAvatarOperationState == .idle)
            #expect(state.userProfile.customCompanionId == oldID)
            #expect(!sentAbort)

            state.customAvatarConnectionProvider = { (true, deviceID) }
            await state.flushPriorityCustomAvatarOperationIfNeeded()

            #expect(sentAbort)
            #expect(!sentFrame)
            #expect(state.pendingCustomAvatarOperation == nil)
            #expect(state.customAvatarOperationState == .idle)
            #expect(state.userProfile.customCompanionId == oldID)

            try await snapshot.restore(removingAssetIDs: [candidate.id, oldID])
        }
    }

    @Test("cancellation on a different device preserves the pending abort")
    func wrongDeviceCancellationKeepsAbortMarker() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let originalDeviceID = UUID()
            let candidate = makeCompanion(id: UUID(), name: "Candidate")
            let operation = makePendingApply(
                companion: candidate,
                oldID: nil,
                deviceID: originalDeviceID,
                kriData: Data([1]),
                phase: .awaitingValidation
            )
            state.pendingCustomAvatarOperation = operation
            state.customAvatarOperationState = .failed("retry")
            state.customAvatarConnectionProvider = { (true, UUID()) }
            var sentCommand = false
            state.avatarControlSender = { _ in sentCommand = true }

            try await state.cancelCustomAvatarOperation()

            #expect(!sentCommand)
            #expect(state.pendingCustomAvatarOperation?.phase == .awaitingAbortResult)
            #expect(state.customAvatarOperationState == .idle)
            #expect(state.lastError == CustomAvatarOperationError.wrongDevice.localizedDescription)

            try await snapshot.restore(removingAssetIDs: [candidate.id])
        }
    }

    @Test("disconnected late AvatarControl result cannot advance an operation")
    func disconnectedLateResultIsIgnored() {
        let state = AppState.makeForTesting()
        let deviceID = UUID()
        let oldID = UUID()
        let candidate = makeCompanion(id: UUID(), name: "Candidate")
        let operation = makePendingApply(
            companion: candidate,
            oldID: oldID,
            deviceID: deviceID,
            kriData: Data([1]),
            phase: .awaitingCommitResult
        )
        state.pendingCustomAvatarOperation = operation
        state.userProfile.customCompanionId = oldID
        state.customAvatarOperationState = .committing
        state.customAvatarConnectionProvider = { (false, deviceID) }

        state.handleAvatarControlResult(
            AvatarControlResult(
                operationID: operation.operationID,
                status: .committed,
                avatarState: .committed,
                customActive: true,
                avatarID: candidate.id,
                byteLength: 1,
                crc32: CRC32.ieee(Data([1]))
            )
        )

        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.userProfile.customCompanionId == oldID)
        #expect(state.customAvatarOperationState == .committing)
        #expect(state.bufferedAvatarControlResults[operation.operationID] == nil)
    }

    @Test("a corrupted apply marker without device identity is never replayed")
    func nilDeviceApplyIsRejected() async {
        let state = AppState.makeForTesting()
        let candidate = makeCompanion(id: UUID(), name: "Candidate")
        let operation = PendingCustomAvatarOperation(
            kind: .apply,
            phase: .awaitingAbortResult,
            operationID: 701,
            avatarID: candidate.id,
            deviceID: nil,
            fileCRC32: 1,
            fileLength: 1,
            candidateCompanion: candidate,
            candidatePreviewFileName: LocalStorage.pendingCustomAvatarPreviewFileName,
            candidateImageFileName: LocalStorage.pendingCustomAvatarImageFileName,
            oldSelection: CustomAvatarSelectionSnapshot(profile: .default)
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarConnectionProvider = { (true, UUID()) }
        var sentCommand = false
        state.avatarControlSender = { _ in sentCommand = true }

        await state.retryCustomAvatarOperation()

        #expect(!sentCommand)
        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.customAvatarOperationState == .failed(
            CustomAvatarOperationError.wrongDevice.localizedDescription
        ))
    }

    private func makeCompanion(id: UUID, name: String) -> CustomCompanion {
        CustomCompanion(
            id: id,
            name: name,
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )
    }

    private func validPNG() throws -> Data {
        try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg=="
        ))
    }

    private func makePendingApply(
        companion: CustomCompanion,
        oldID: UUID?,
        deviceID: UUID,
        kriData: Data,
        phase: PendingCustomAvatarPhase
    ) -> PendingCustomAvatarOperation {
        PendingCustomAvatarOperation(
            kind: .apply,
            phase: phase,
            operationID: 700,
            avatarID: companion.id,
            deviceID: deviceID,
            fileCRC32: CRC32.ieee(kriData),
            fileLength: kriData.count,
            candidateCompanion: companion,
            candidatePreviewFileName: LocalStorage.pendingCustomAvatarPreviewFileName,
            candidateImageFileName: LocalStorage.pendingCustomAvatarImageFileName,
            oldSelection: CustomAvatarSelectionSnapshot(
                builtInCharacter: .joy,
                customCompanionID: oldID,
                intimacyStage: .closeFriend
            )
        )
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
