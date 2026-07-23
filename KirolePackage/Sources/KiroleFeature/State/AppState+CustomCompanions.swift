// NOTE: try? is discouraged in this codebase. Use do-try-catch + ErrorReporter.log instead.
import Foundation

extension AppState {
    // MARK: - Public lifecycle

    /// Creates and applies a companion as one firmware-confirmed transaction. Neither the
    /// companion list nor active identity changes before the device reports `committed`.
    @discardableResult
    public func addCustomCompanion(
        name: String,
        relationship: CompanionRelationship,
        personaVoice: CompanionPersonaVoice,
        customPrompt: String = "",
        curiosityLevel: Double = 0.5,
        humorLevel: Double = 0.5,
        strictnessLevel: Double = 0.3,
        backstory: String = "",
        sensitiveBoundary: String = "",
        previewData: Data,
        imageData: Data
    ) async throws -> CustomCompanion {
        let id = UUID()
        let companion = CustomCompanion(
            id: id,
            name: name,
            relationship: relationship,
            personaVoice: personaVoice,
            customPrompt: customPrompt,
            curiosityLevel: curiosityLevel,
            humorLevel: humorLevel,
            strictnessLevel: strictnessLevel,
            backstory: backstory,
            sensitiveBoundary: sensitiveBoundary,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )
        try await applyCustomCompanion(
            companion,
            previewData: previewData,
            imageData: imageData
        )
        return companion
    }

    /// Metadata is local-only and remains editable offline. Immutable identity, asset names and
    /// creation time come from the stored record, not from a potentially stale UI draft.
    @discardableResult
    public func updateCustomCompanionMetadata(
        _ updated: CustomCompanion
    ) async throws -> CustomCompanion {
        guard let index = customCompanions.firstIndex(where: { $0.id == updated.id }) else {
            throw CustomAvatarOperationError.companionNotFound
        }
        let existing = customCompanions[index]
        let merged = existing.updatingMetadata(from: updated, updatedAt: Date())
        var newList = customCompanions
        newList[index] = merged
        try await localStorage.saveCustomCompanions(newList)
        customCompanions = newList
        if userProfile.customCompanionId == merged.id {
            await refreshSharedPetDialogueIfNeeded()
            await refreshHomeCompanionPresentation()
        }
        return merged
    }

    @discardableResult
    public func saveCustomCompanionAsNew(
        from companion: CustomCompanion,
        previewData: Data,
        imageData: Data
    ) async throws -> CustomCompanion {
        try await addCustomCompanion(
            name: companion.name,
            relationship: companion.relationship,
            personaVoice: companion.personaVoice,
            customPrompt: companion.customPrompt,
            curiosityLevel: companion.curiosityLevel,
            humorLevel: companion.humorLevel,
            strictnessLevel: companion.strictnessLevel,
            backstory: companion.backstory,
            sensitiveBoundary: companion.sensitiveBoundary,
            previewData: previewData,
            imageData: imageData
        )
    }

    /// Replaces metadata and photo as one firmware-confirmed transaction. The stored companion
    /// remains unchanged until the device commits the candidate image.
    @discardableResult
    public func replaceCustomCompanion(
        _ updated: CustomCompanion,
        previewData: Data,
        imageData: Data
    ) async throws -> CustomCompanion {
        guard let companion = customCompanions.first(where: { $0.id == updated.id }) else {
            throw CustomAvatarOperationError.companionNotFound
        }
        // Product rule: an inactive companion must be applied first; the device owns one slot.
        guard userProfile.customCompanionId == companion.id else {
            throw CustomAvatarOperationError.deviceRejected(
                "Apply this companion before replacing its photo."
            )
        }
        let candidate = companion.updatingMetadata(from: updated, updatedAt: Date())
        try await applyCustomCompanion(
            candidate,
            previewData: previewData,
            imageData: imageData
        )
        return candidate
    }

    public func replaceCustomCompanionPhoto(
        id: UUID,
        previewData: Data,
        imageData: Data
    ) async throws {
        guard let companion = customCompanions.first(where: { $0.id == id }) else {
            throw CustomAvatarOperationError.companionNotFound
        }
        _ = try await replaceCustomCompanion(
            companion,
            previewData: previewData,
            imageData: imageData
        )
    }

    /// Applies an existing custom companion. The prior App identity remains authoritative for
    /// the entire transfer and only changes after a matching firmware `committed` result.
    public func selectCustomCompanion(id: UUID) async throws {
        guard let companion = customCompanions.first(where: { $0.id == id }) else {
            throw CustomAvatarOperationError.companionNotFound
        }
        guard userProfile.customCompanionId != id else { return }
        guard let previewData = await localStorage.loadCustomCompanionPreview(id: id),
              let imageData = await localStorage.loadCustomCompanionImageData(id: id) else {
            throw CustomAvatarOperationError.missingAvatarData
        }
        try await applyCustomCompanion(
            companion,
            previewData: previewData,
            imageData: imageData
        )
    }

    /// Online deletion waits for an idempotent `eraseExact` result before touching local data.
    /// Offline deletion removes local personal data immediately and, when the target device is
    /// known, leaves a UUID-only marker for the next connection.
    public func deleteCustomCompanion(id: UUID) async throws {
        guard customCompanions.contains(where: { $0.id == id }) else {
            if pendingCustomAvatarOperation?.kind == .eraseExact,
               pendingCustomAvatarOperation?.avatarID == id {
                return
            }
            return
        }
        try ensureNoCustomAvatarOperation()
        let connection = customAvatarConnectionProvider()
        guard let deviceID = connection.deviceID else {
            try await removeLocalCustomCompanion(id: id)
            ErrorReporter.log(
                .sync(
                    component: "Custom Avatar Cleanup",
                    underlying: "Deleted local companion data without scheduling hardware erase because no device identity is known."
                ),
                context: "AppState.deleteCustomCompanion.noDeviceIdentity"
            )
            customAvatarOperationState = .idle
            return
        }
        let operation = PendingCustomAvatarOperation(
            kind: .eraseExact,
            phase: .awaitingEraseResult,
            operationID: nextCustomAvatarOperationID(),
            avatarID: id,
            deviceID: deviceID,
            fileCRC32: 0,
            fileLength: 0,
            candidateCompanion: nil,
            candidatePreviewFileName: nil,
            candidateImageFileName: nil,
            oldSelection: CustomAvatarSelectionSnapshot(profile: userProfile)
        )
        pendingCustomAvatarOperation = operation

        if !connection.isConnected {
            do {
                try await persistPendingCustomAvatarOperation(operation)
                try await removeLocalCustomCompanion(id: id)
                // Deletion is complete from the user's point of view. Keep the erase marker
                // silent; BLESyncCoordinator consumes it automatically after reconnect.
                customAvatarOperationState = .idle
            } catch {
                markCustomAvatarOperationFailure(error)
                throw error
            }
            return
        }

        let generation = beginCustomAvatarOperationGeneration()
        do {
            try await persistPendingCustomAvatarOperation(operation)
            try await runPendingErase(operation, generation: generation)
        } catch {
            if isCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            ) {
                markCustomAvatarOperationFailure(error)
            }
            throw error
        }
    }

    // MARK: - Built-in selection

    public func selectBuiltInCompanion(_ character: CompanionCharacter) async throws {
        guard !customAvatarOperationState.isInProgress
                || customAvatarOperationState.canCancel else {
            throw CustomAvatarOperationError.commitAlreadyStarted
        }
        if pendingCustomAvatarOperation?.kind == .apply {
            try await cancelCustomAvatarOperation()
            guard pendingCustomAvatarOperation == nil else {
                throw CustomAvatarOperationError.deviceNotConnected
            }
        }

        let isDifferentIdentity = userProfile.currentSelection != .builtIn(character)
        var profile = userProfile
        profile.companionCharacter = character
        profile.customCompanionId = nil
        if isDifferentIdentity {
            let usage = try await localStorage.loadCompanionUsageState()
                ?? CompanionUsageState()
            profile.intimacyStage = IntimacyStage.from(
                bindingDays: usage.progress(for: character).totalUsedDays
            )
        }
        try await localStorage.saveUserProfile(profile)
        userProfile = profile
        sendPetStatusNow(customActive: false, context: "AppState.selectBuiltInCompanion")
        requestBLESync(reason: "selectBuiltInCompanion")
    }

    // MARK: - Operation controls

    public func retryCustomAvatarOperation() async {
        guard !isCustomAvatarRetryRunning else { return }
        isCustomAvatarRetryRunning = true
        defer { isCustomAvatarRetryRunning = false }
        do {
            if pendingCustomAvatarOperation == nil {
                await restorePendingCustomAvatarOperation()
            }
            guard let operation = pendingCustomAvatarOperation else { return }
            try ensureExpectedDeviceConnected(operation)
            let generation = beginCustomAvatarOperationGeneration()

            switch operation.kind {
            case .apply:
                if operation.phase == .awaitingAbortResult {
                    try await runPendingAbort(operation, generation: generation)
                    return
                }
                guard let candidate = operation.candidateCompanion,
                      await localStorage.loadPendingCustomAvatarPreviewData() != nil,
                      let imageData = await localStorage.loadPendingCustomAvatarImageData() else {
                    throw CustomAvatarOperationError.missingAvatarData
                }
                if operation.phase == .preparing || operation.fileLength == 0 {
                    try await runApplyTransaction(
                        operation,
                        companion: candidate,
                        imageData: imageData,
                        generation: generation
                    )
                    return
                }
                customAvatarOperationState = .validating
                switch try await pendingApplyRecoveryDisposition(
                    operation,
                    generation: generation
                ) {
                case .committed:
                    // Query proved the device commit. Claim the non-cancellable local finalizer
                    // before its first storage await so sign-out cannot replace this operation.
                    customAvatarOperationState = .committing
                    try await finalizeCommittedApply(operation)
                case .staged:
                    try await commitStagedApply(operation, generation: generation)
                case .retransmit:
                    try await runApplyTransaction(
                        operation,
                        companion: candidate,
                        imageData: imageData,
                        generation: generation
                    )
                }
            case .eraseExact, .eraseAll:
                try await runPendingErase(operation, generation: generation)
            }
        } catch {
            if pendingCustomAvatarOperation != nil,
               !(error is CancellationError) {
                markCustomAvatarOperationFailure(error)
            }
        }
    }

    public func cancelCustomAvatarOperation() async throws {
        guard var operation = pendingCustomAvatarOperation else {
            invalidateCustomAvatarOperationGeneration()
            customAvatarPushTask?.cancel()
            customAvatarPushTask = nil
            resumeAvatarControlWaiter(throwing: CancellationError())
            customAvatarOperationState = .idle
            return
        }
        guard operation.kind == .apply else {
            throw CustomAvatarOperationError.commitAlreadyStarted
        }
        guard operation.phase != .awaitingCommitResult else {
            throw CustomAvatarOperationError.commitAlreadyStarted
        }

        invalidateCustomAvatarOperationGeneration()
        customAvatarPushTask?.cancel()
        customAvatarPushTask = nil
        resumeAvatarControlWaiter(throwing: CancellationError())

        if operation.phase == .preparing || operation.phase == .prepared {
            try await clearPendingCustomAvatarOperation()
            customAvatarOperationState = .idle
            return
        }

        guard operation.phase == .transferring
                || operation.phase == .awaitingValidation
                || operation.phase == .awaitingAbortResult else {
            throw CustomAvatarOperationError.commitAlreadyStarted
        }
        operation.phase = .awaitingAbortResult
        try await persistPendingCustomAvatarOperation(operation)

        let connection = customAvatarConnectionProvider()
        guard connection.isConnected,
              let expectedDeviceID = operation.deviceID,
              expectedDeviceID == connection.deviceID else {
            let error: CustomAvatarOperationError = connection.isConnected
                ? .wrongDevice
                : .deviceNotConnected
            lastError = error.localizedDescription
            customAvatarOperationState = .idle
            return
        }

        let generation = beginCustomAvatarOperationGeneration()
        do {
            try await runPendingAbort(operation, generation: generation)
        } catch {
            if isCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            ) {
                markCustomAvatarOperationFailure(error)
            }
            throw error
        }
    }

    /// iOS does not guarantee a multi-minute BLE transfer in the background. Pre-commit work
    /// stops immediately but remains durable for query/retry when the app returns.
    public func interruptCustomAvatarOperationForBackground() {
        guard customAvatarOperationState.canCancel,
              pendingCustomAvatarOperation?.kind == .apply else { return }
        interruptCustomAvatarOperation(
            message: "Photo transfer paused when Kirole moved to the background. Reconnect and retry."
        )
    }

    /// Called by BLEService on an actual disconnect. Commit/erase results are recovered by query;
    /// no abort is sent because the peripheral is already unavailable.
    public func handleCustomAvatarDeviceDisconnected() {
        guard pendingCustomAvatarOperation != nil,
              customAvatarOperationState.isInProgress else { return }
        interruptCustomAvatarOperation(
            message: "Kirole disconnected. Reconnect it to verify or resend the companion image."
        )
    }

    public var canCancelCustomAvatarOperation: Bool {
        guard let operation = pendingCustomAvatarOperation,
              operation.kind == .apply,
              operation.phase != .awaitingCommitResult else {
            return false
        }
        return customAvatarOperationState.canCancel
            || !customAvatarOperationState.isInProgress
    }

    public func resetCustomAvatarOperationState() {
        guard !customAvatarOperationState.isInProgress,
              pendingCustomAvatarOperation?.kind != .apply else { return }
        customAvatarOperationState = .idle
    }

    /// Called by `BLEService` after decrypting and decoding a v2.7 result. A late result for an
    /// old operation is ignored and can never commit a newer candidate.
    public func handleAvatarControlResult(_ result: AvatarControlResult) {
        guard let operation = pendingCustomAvatarOperation,
              operation.operationID == result.operationID else { return }
        let connection = customAvatarConnectionProvider()
        guard connection.isConnected else { return }
        guard let expectedDeviceID = operation.deviceID,
              expectedDeviceID == connection.deviceID else {
            let error = CustomAvatarOperationError.wrongDevice
            resumeAvatarControlWaiter(throwing: error)
            customAvatarOperationState = .failed(
                error.localizedDescription
            )
            return
        }
        if let waiter = avatarControlResultWaiter,
           waiter.operationID == result.operationID,
           waiter.expectedStatus == result.status {
            avatarControlResultWaiter = nil
            avatarControlTimeoutTask?.cancel()
            avatarControlTimeoutTask = nil
            avatarControlExpectedBufferedStatus = nil
            waiter.continuation.resume(returning: result)
            return
        }
        guard canBufferAvatarControlResult(result, operation: operation) else { return }
        bufferedAvatarControlResults[result.operationID, default: []].append(result)
    }

    /// BLESyncCoordinator invokes this after reconnect. The old UUID retry/back-off queue is
    /// retired; v2.7 resumes the single durable apply/erase transaction instead.
    public func flushPendingCustomCompanionPushIfNeeded() async {
        if pendingCustomAvatarOperation == nil {
            await restorePendingCustomAvatarOperation()
        }
        guard pendingCustomAvatarOperation != nil,
              customAvatarConnectionProvider().isConnected,
              !customAvatarOperationState.isInProgress else { return }
        await retryCustomAvatarOperation()
    }

    /// Erases and pending cancellations run before routine Time/PetStatus/DayPack writes.
    /// A normal apply stays in the later slot so its multi-minute transfer does not block sync.
    public func flushPriorityCustomAvatarOperationIfNeeded() async {
        if pendingCustomAvatarOperation == nil {
            await restorePendingCustomAvatarOperation()
        }
        guard let operation = pendingCustomAvatarOperation,
              operation.requiresPriorityBLEFlush,
              customAvatarConnectionProvider().isConnected,
              !customAvatarOperationState.isInProgress else { return }
        await retryCustomAvatarOperation()
    }

    /// DeviceWake inventory is only a recovery hint. It lacks `CustomActive`, so matching bytes
    /// cannot prove that firmware activated the candidate. The returned flag asks the sync
    /// coordinator to resume the durable operation through `AvatarControl.query`.
    @discardableResult
    public func reconcileCustomAvatarInventory(
        hasImage _: Bool,
        avatarID _: UUID?,
        byteLength _: UInt32,
        reportedCRC32 _: UInt32
    ) async -> Bool {
        guard let operation = pendingCustomAvatarOperation else { return false }
        let connection = customAvatarConnectionProvider()
        guard connection.isConnected,
              let expectedDeviceID = operation.deviceID,
              expectedDeviceID == connection.deviceID else {
            customAvatarOperationState = .failed(
                CustomAvatarOperationError.wrongDevice.localizedDescription
            )
            return false
        }
        // Never race the transaction that already owns the same operation. Its staged/committed
        // 0x22 result remains authoritative; a later DeviceWake can trigger query recovery.
        guard !customAvatarOperationState.isInProgress else { return false }
        return true
    }

    // MARK: - Sign out / account removal

    /// Erases all custom-avatar data. If the device is unavailable, only a small `eraseAll`
    /// marker survives sign-out so the next connection can finish the hardware cleanup.
    public func prepareCustomCompanionDataForSignOut() async throws {
        try await prepareCustomCompanionDataForAccountRemoval()
    }

    /// Reserved for the future account-deletion UI; intentionally shares the exact cleanup path.
    public func prepareCustomCompanionDataForAccountRemoval() async throws {
        guard customAvatarOperationState != .erasing,
              customAvatarOperationState != .committing else {
            throw CustomAvatarOperationError.operationInProgress
        }
        // Claim and invalidate the single avatar-operation slot before the first suspension.
        // A commit that already reached its non-cancellable local finalizer must finish first.
        customAvatarOperationState = .erasing
        invalidateCustomAvatarOperationGeneration()
        customAvatarPushTask?.cancel()
        customAvatarPushTask = nil
        resumeAvatarControlWaiter(throwing: CancellationError())
        await ensureInitialLoadComplete()
        let connection = customAvatarConnectionProvider()
        let oldOperation = pendingCustomAvatarOperation
        let hasLocalCustomData = !customCompanions.isEmpty
            || userProfile.customCompanionId != nil
            || oldOperation != nil
        if !hasLocalCustomData, connection.deviceID == nil {
            do {
                // The JSON index and operation marker are not authoritative for private bytes:
                // either may be missing after a partial write or development reset.
                try await localStorage.deleteCustomCompanionIndex()
                try await localStorage.deleteAllCustomCompanionAssets()
                try await clearPendingCustomAvatarOperation()
                customAvatarOperationState = .idle
                return
            } catch {
                markCustomAvatarOperationFailure(error)
                throw error
            }
        }
        guard let targetDeviceID = oldOperation?.deviceID ?? connection.deviceID else {
            do {
                try await removeAllLocalCustomCompanionData()
                try await clearPendingCustomAvatarOperation()
                customAvatarOperationState = .idle
                ErrorReporter.log(
                    .sync(
                        component: "Custom Avatar Cleanup",
                        underlying: "Deleted local companion data without scheduling hardware erase because no device identity is known."
                    ),
                    context: "AppState.accountRemoval.noDeviceIdentity"
                )
                return
            } catch {
                markCustomAvatarOperationFailure(error)
                throw error
            }
        }
        if connection.isConnected, connection.deviceID != targetDeviceID {
            let error = CustomAvatarOperationError.wrongDevice
            customAvatarOperationState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }
        if let oldOperation,
           oldOperation.kind == .apply,
           oldOperation.phase != .awaitingCommitResult,
           customAvatarConnectionProvider().isConnected {
            do {
                try await avatarControlSender(.abort(operationID: oldOperation.operationID))
            } catch {
                ErrorReporter.log(error, context: "AppState.accountRemoval.abortAvatar")
            }
        }
        try await clearPendingCustomAvatarOperation()

        let operation = PendingCustomAvatarOperation(
            kind: .eraseAll,
            phase: .awaitingEraseResult,
            operationID: nextCustomAvatarOperationID(),
            avatarID: nil,
            deviceID: targetDeviceID,
            fileCRC32: 0,
            fileLength: 0,
            candidateCompanion: nil,
            candidatePreviewFileName: nil,
            candidateImageFileName: nil,
            oldSelection: CustomAvatarSelectionSnapshot(profile: userProfile)
        )
        let generation = beginCustomAvatarOperationGeneration()
        do {
            try await persistPendingCustomAvatarOperation(operation)
            if connection.isConnected {
                try await runPendingErase(operation, generation: generation)
            } else {
                customAvatarOperationState = .interrupted(
                    "Kirole will erase the saved photo when it reconnects."
                )
            }
        } catch {
            if isCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            ) {
                markCustomAvatarOperationFailure(error)
            }
            throw error
        }
        if !connection.isConnected {
            try await removeAllLocalCustomCompanionData()
        }
    }

    // MARK: - Derived state

    public var activeCustomCompanion: CustomCompanion? {
        guard let id = userProfile.customCompanionId else { return nil }
        return customCompanions.first { $0.id == id }
    }
}
